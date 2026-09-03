#!/usr/bin/env python3

# cf-api-throttle.py - a loopback rate limiter in front of the Cloudflare API.
#
# WHY THIS EXISTS
# ---------------
# Cloudflare allows 1200 API requests per five minutes per credential. The
# zones layer holds one cloudflare_zone, one cloudflare_zone_rules and roughly
# seven cloudflare_zone_setting resources per zone, and every one of them is a
# GET on every refresh. At a few hundred zones that is thousands of reads in a
# single plan, and Terraform issues them as fast as its scheduler allows.
#
# The Cloudflare Terraform provider was able to pace itself in 4.x - `rps`,
# `retries`, `min_backoff` and `max_backoff` were provider arguments. The 5.x
# rewrite dropped all four and never replaced them, so a 5.x provider has no
# rate limiting and no 429 retry at all:
#   https://github.com/cloudflare/terraform-provider-cloudflare/issues/5505
# The run fails partway through with
#   429 {"code":971,"message":"Please wait and consider throttling your request speed"}
# surfaced as "failed to make http request" against whichever resource happened
# to be in flight.
#
# `-parallelism` alone does not fix this. It caps how many resources Terraform
# works on at once, not the request rate: even at -parallelism=1 a sequence of
# fast reads sustains well over four per second, which is the ceiling 1200/5min
# works out to.
#
# So the pacing is done here instead. The provider's base URL is pointed at this
# process, every request waits for a token from a shared bucket, and a 429 that
# still gets through is retried here with the API's own Retry-After rather than
# failing the resource. Terraform sees a slow API, not a rate-limited one, and
# the run takes as long as the rate limit says it must.
#
# CREDENTIAL HANDLING - read before changing anything below
# ---------------------------------------------------------
# Every proxied request carries the Cloudflare bearer token in its Authorization
# header, so this process handles a live credential:
#
#   * The listener binds to 127.0.0.1 only. Nothing off the host can reach it,
#     which is also why plaintext HTTP on the inbound hop is acceptable - it
#     never leaves the loopback interface. The outbound hop to Cloudflare is
#     always HTTPS.
#   * Request and response headers and bodies are NEVER logged. The log carries
#     method, path, status and timing, nothing else. Do not add header or body
#     logging for debugging; a run log is retained far longer than a token
#     rotation cycle.
#   * Nothing is written to disk. No cache, no request log, no state file.
#   * The upstream host is fixed by --upstream and defaults to the real API, so
#     a poisoned environment variable cannot redirect credentialed traffic to an
#     arbitrary host.
#
# USAGE
#   python3 cf-api-throttle.py --rps 3.5 --port 8787 &
#   export CLOUDFLARE_BASE_URL="http://127.0.0.1:8787/client/v4"
#
# Terminating it with SIGTERM or SIGINT prints a summary of what it absorbed.

import argparse
import http.client
import json
import os
import random
import signal
import socket
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_DEFAULT = "api.cloudflare.com"
API_PREFIX = "/client/v4"
HEALTH_PATH = "/__throttle/health"

# RFC 7230 hop-by-hop headers. They describe a single connection and must not be
# forwarded across one, in either direction. Transfer-Encoding matters most:
# every response is re-sent here with an explicit Content-Length, so passing the
# upstream's chunked encoding through would describe a framing that no longer
# applies.
HOP_BY_HOP = frozenset(
    [
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "host",
        "content-length",
    ]
)

# A 429 means the request was rejected before it was acted on, so retrying it is
# safe whatever the method. A 5xx or a dropped connection is ambiguous - the
# write may already have landed - so those are only retried for methods where a
# repeat cannot create a second resource. POST is absent deliberately: retrying
# a POST that returned 502 is how you get two of something.
IDEMPOTENT = frozenset(["GET", "HEAD", "OPTIONS", "PUT", "DELETE"])


class TokenBucket:
    """Shared rate limiter. Blocks the calling thread until a token is free.

    A bucket rather than a fixed sleep between requests because Cloudflare's
    limit is a budget over a window, not a minimum spacing: a short burst is
    fine as long as the average holds. `burst` is how much of the budget may be
    spent at once, and is kept small so a burst cannot eat a meaningful slice of
    the 1200 and leave the rest of the run starved.
    """

    def __init__(self, rps, burst):
        self._rps = float(rps)
        self._burst = float(burst)
        self._tokens = float(burst)
        self._updated = time.monotonic()
        self._lock = threading.Lock()

    def take(self):
        """Consume one token, sleeping if necessary. Returns seconds waited."""
        with self._lock:
            now = time.monotonic()
            self._tokens = min(self._burst, self._tokens + (now - self._updated) * self._rps)
            self._updated = now
            if self._tokens >= 1.0:
                self._tokens -= 1.0
                return 0.0
            # The sleep happens while the lock is held on purpose. It serialises
            # waiting threads into arrival order and, more importantly, keeps the
            # deficit accounting honest - releasing the lock first would let every
            # waiting thread compute its wait against the same empty bucket and
            # then all wake together, which is the burst this exists to prevent.
            wait = (1.0 - self._tokens) / self._rps
            time.sleep(wait)
            self._tokens = 0.0
            self._updated = time.monotonic()
            return wait


class Stats:
    def __init__(self):
        self._lock = threading.Lock()
        self.requests = 0
        self.throttled_429 = 0
        self.retries = 0
        self.errors = 0
        self.wait_total = 0.0
        self.wait_max = 0.0

    def record(self, wait):
        with self._lock:
            self.requests += 1
            self.wait_total += wait
            self.wait_max = max(self.wait_max, wait)

    def bump(self, field):
        with self._lock:
            setattr(self, field, getattr(self, field) + 1)

    def summary(self):
        with self._lock:
            mean = self.wait_total / self.requests if self.requests else 0.0
            return (
                f"requests={self.requests} 429s_absorbed={self.throttled_429} "
                f"retries={self.retries} upstream_errors={self.errors} "
                f"queue_wait_mean={mean:.2f}s queue_wait_max={self.wait_max:.2f}s"
            )


class Upstream:
    """One HTTPS connection per worker thread, reused across requests.

    Connection reuse is not an optimisation here so much as a correctness aid: a
    fresh TLS handshake per request would double the traffic Cloudflare sees from
    this host and add latency that the token bucket would then pace on top of.
    """

    def __init__(self, host, timeout):
        self.host = host
        self._timeout = timeout
        self._local = threading.local()
        self._ctx = ssl.create_default_context()

    def connection(self):
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = http.client.HTTPSConnection(
                self.host, timeout=self._timeout, context=self._ctx
            )
            self._local.conn = conn
        return conn

    def drop(self):
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
            self._local.conn = None

    def send(self, method, path, headers, body):
        """Returns (status, header_items, body_bytes). Raises on transport failure."""
        conn = self.connection()
        try:
            conn.request(method, path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            return resp.status, resp.getheaders(), data
        except Exception:
            # A reused connection the far end has already closed fails on the
            # write, not the read. Drop it so the retry gets a fresh one.
            self.drop()
            raise


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # Injected by main().
    bucket = None
    stats = None
    upstream = None
    max_attempts = 5
    max_backoff = 30.0
    verbose = False

    def log_message(self, fmt, *args):
        # BaseHTTPRequestHandler's default writes the request line to stderr for
        # every request. Silenced because the request line is the only place a
        # query string could carry something identifying, and because a
        # per-request line across thousands of requests buries the run log.
        pass

    def _note(self, msg):
        if self.verbose:
            sys.stderr.write(f"[throttle] {msg}\n")
            sys.stderr.flush()

    # ------------------------------------------------------------------
    def _normalise_path(self):
        """Ensure the path carries the API prefix.

        The provider resolves request paths against CLOUDFLARE_BASE_URL, and
        whether the resolution keeps a trailing path segment depends on whether
        that URL ends in a slash. Both spellings are accepted rather than made a
        deployment detail nobody remembers: a path that already starts with
        /client/v4 is passed through, and one that does not gets the prefix.
        """
        path = self.path
        if not path.startswith("/"):
            path = "/" + path
        if path.startswith(API_PREFIX + "/") or path == API_PREFIX:
            return path
        return API_PREFIX + path

    def _request_headers(self):
        headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP:
                continue
            headers[key] = value
        # Set explicitly rather than forwarded: the inbound Host names the
        # loopback listener, and Cloudflare's edge routes on Host.
        headers["Host"] = self.upstream.host
        return headers

    def _read_body(self):
        length = self.headers.get("Content-Length")
        if length:
            try:
                return self.rfile.read(int(length))
            except ValueError:
                return None
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            # The Cloudflare provider always sends a Content-Length, so this is a
            # guard rather than a path in use. Reading a chunked body correctly
            # needs the de-chunking http.client does on responses but not on
            # inbound server requests, so it is refused rather than mishandled.
            self._fail(411, "chunked request bodies are not proxied")
            return False
        return None

    def _fail(self, status, message):
        """Answer with a JSON error shaped like the Cloudflare API's own.

        The provider parses the body to build its error message. Returning the
        API's envelope means a proxy failure surfaces as a readable message
        against the offending resource instead of a JSON decode error.
        """
        body = json.dumps(
            {
                "success": False,
                "errors": [{"code": 0, "message": f"cf-api-throttle: {message}"}],
                "messages": [],
                "result": None,
            }
        ).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @staticmethod
    def _retry_after(headers, attempt, max_backoff):
        """Seconds to wait. Prefers the API's own Retry-After.

        Falls back to exponential backoff with full jitter. The jitter matters
        because several Terraform worker threads hit the limit within the same
        instant, and a deterministic backoff would march them back into the API
        together.
        """
        for name, value in headers:
            if name.lower() == "retry-after":
                try:
                    return min(max_backoff, max(1.0, float(value.strip())))
                except (TypeError, ValueError):
                    break
        return min(max_backoff, random.uniform(1.0, 2.0 ** attempt))

    # ------------------------------------------------------------------
    def _proxy(self):
        if self.path == HEALTH_PATH:
            # Answered before the bucket is touched: the readiness probe must not
            # spend part of the request budget it is checking the guard on.
            body = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        body = self._read_body()
        if body is False:  # _fail already answered
            return

        path = self._normalise_path()
        headers = self._request_headers()
        method = self.command
        retryable_transport = method in IDEMPOTENT

        last_error = None
        for attempt in range(self.max_attempts):
            self.stats.record(self.bucket.take())
            try:
                status, resp_headers, resp_body = self.upstream.send(
                    method, path, headers, body
                )
            except Exception as exc:  # transport failure, not an HTTP error
                self.stats.bump("errors")
                last_error = f"{type(exc).__name__}: {exc}"
                if not retryable_transport or attempt == self.max_attempts - 1:
                    break
                self.stats.bump("retries")
                delay = min(self.max_backoff, random.uniform(1.0, 2.0 ** attempt))
                self._note(f"{method} {path}: {last_error}, retrying in {delay:.1f}s")
                time.sleep(delay)
                continue

            should_retry = status == 429 or (status >= 500 and retryable_transport)
            if should_retry and attempt < self.max_attempts - 1:
                if status == 429:
                    self.stats.bump("throttled_429")
                self.stats.bump("retries")
                delay = self._retry_after(resp_headers, attempt, self.max_backoff)
                self._note(
                    f"{method} {path}: {status}, waiting {delay:.1f}s "
                    f"(attempt {attempt + 1}/{self.max_attempts})"
                )
                time.sleep(delay)
                continue

            if status == 429:
                # Out of attempts. Passed through rather than rewritten so the
                # provider reports Cloudflare's own error, and so the run log
                # shows the rate limit was hit despite the pacing - which means
                # --rps is set too high for this credential.
                self.stats.bump("throttled_429")
                self._note(
                    f"{method} {path}: 429 after {self.max_attempts} attempts, "
                    "passing it to Terraform - lower --rps"
                )

            self._respond(status, resp_headers, resp_body)
            return

        self._fail(
            502,
            f"upstream {method} {path} failed after {self.max_attempts} attempts: "
            f"{last_error or 'rate limited'}",
        )

    def _respond(self, status, resp_headers, resp_body):
        self.send_response(status)
        for name, value in resp_headers:
            if name.lower() in HOP_BY_HOP:
                continue
            self.send_header(name, value)
        # Always explicit, and always the length of exactly what is about to be
        # written. Content-Encoding is forwarded untouched above and the body is
        # never decompressed here, so the two stay consistent.
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(resp_body)

    # Every method the Cloudflare API uses. BaseHTTPRequestHandler dispatches on
    # the name, so each one has to exist even though they all do the same thing.
    do_GET = _proxy
    do_HEAD = _proxy
    do_POST = _proxy
    do_PUT = _proxy
    do_PATCH = _proxy
    do_DELETE = _proxy
    do_OPTIONS = _proxy


def main():
    parser = argparse.ArgumentParser(
        description="Loopback rate limiter for the Cloudflare API."
    )
    parser.add_argument(
        "--rps",
        type=float,
        default=float(os.environ.get("CF_THROTTLE_RPS", "3.5")),
        help=(
            "Sustained requests per second. Cloudflare allows 1200 per 5 minutes, "
            "which is 4.0/s; the 3.5 default leaves headroom for anything else "
            "using the same credential."
        ),
    )
    parser.add_argument(
        "--burst",
        type=float,
        default=float(os.environ.get("CF_THROTTLE_BURST", "8")),
        help="Requests allowed back-to-back before pacing applies.",
    )
    parser.add_argument("--port", type=int, default=int(os.environ.get("CF_THROTTLE_PORT", "8787")))
    parser.add_argument(
        "--upstream",
        default=os.environ.get("CF_THROTTLE_UPSTREAM", UPSTREAM_DEFAULT),
        help="Upstream API host. Fixed at start; requests cannot redirect it.",
    )
    parser.add_argument("--max-attempts", type=int, default=5)
    parser.add_argument(
        "--max-backoff",
        type=float,
        default=30.0,
        help="Ceiling on a single retry wait, in seconds.",
    )
    parser.add_argument("--timeout", type=float, default=60.0, help="Upstream socket timeout.")
    parser.add_argument(
        "--verbose",
        action="store_true",
        default=os.environ.get("CF_THROTTLE_VERBOSE") == "1",
        help="Log retries and 429s. Never logs headers or bodies.",
    )
    args = parser.parse_args()

    if args.rps <= 0:
        parser.error("--rps must be greater than zero")
    if args.burst < 1:
        parser.error("--burst must be at least 1")

    stats = Stats()
    Handler.bucket = TokenBucket(args.rps, args.burst)
    Handler.stats = stats
    Handler.upstream = Upstream(args.upstream, args.timeout)
    Handler.max_attempts = args.max_attempts
    Handler.max_backoff = args.max_backoff
    Handler.verbose = args.verbose

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        # Terraform opens a connection per worker thread and holds it. Without
        # this the listen backlog is 5 and a burst of workers connecting at once
        # gets connection-refused rather than queued.
        request_queue_size = 128
        address_family = socket.AF_INET

    # 127.0.0.1, never 0.0.0.0: every request through here carries a live
    # Cloudflare API token, and the inbound hop is plaintext.
    server = Server(("127.0.0.1", args.port), Handler)

    def shutdown(signum, _frame):
        sys.stderr.write(f"[throttle] {stats.summary()}\n")
        sys.stderr.flush()
        # From a signal handler, on a thread of its own: shutdown() blocks until
        # serve_forever returns, and calling it on the serving thread deadlocks.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    sys.stderr.write(
        f"[throttle] listening on 127.0.0.1:{args.port} -> https://{args.upstream}{API_PREFIX} "
        f"at {args.rps} req/s (burst {args.burst:g}, {args.max_attempts} attempts)\n"
    )
    sys.stderr.flush()
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
