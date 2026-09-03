#!/usr/bin/env python3

# Tests for cf-api-throttle.py.
#
# The limiter sits in the credential path of every plan and apply: it sees the
# Cloudflare bearer token, decides which failed requests are safe to repeat, and
# is the only thing keeping a run inside the API budget. A silent regression in
# it means either a fleet-wide 429 or - worse - a retried write. So it is tested
# rather than trusted, for the same reason tf-matrix.sh is.
#
# No network and no credentials: the upstream is a fake that records what it was
# handed and replays a scripted sequence of responses, which is what makes the
# retry rules assertable at all. Run it from the repository root:
#
#   python3 .github/scripts/cf-api-throttle-test.py

import importlib.util
import json
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.path.join(HERE, "cf-api-throttle.py")

spec = importlib.util.spec_from_file_location("cf_api_throttle", TARGET)
throttle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(throttle)

OK = (200, [("Content-Type", "application/json")], b'{"success":true}')
# A real Cloudflare 429 carries Retry-After. Kept tiny so the suite stays fast
# while still proving the header is read rather than ignored in favour of the
# backoff.
RATE_LIMITED = (
    429,
    [("Retry-After", "0.01"), ("Content-Type", "application/json")],
    b'{"success":false,"errors":[{"code":971,"message":"Please wait"}]}',
)
BAD_GATEWAY = (502, [], b"bad gateway")


class FakeUpstream:
    """Stands in for Cloudflare. Records every forwarded request."""

    host = "api.cloudflare.com"

    def __init__(self, script):
        self.script = list(script)
        self.calls = []
        self._lock = threading.Lock()

    def send(self, method, path, headers, body):
        with self._lock:
            self.calls.append(
                {"method": method, "path": path, "headers": dict(headers), "body": body}
            )
            if not self.script:
                raise AssertionError(f"unscripted upstream call: {method} {path}")
            item = self.script.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


class Proxy:
    """The real handler, wired to a fake upstream, on an ephemeral port.

    Port 0 rather than a fixed one: the suite starts and stops a server per case,
    and a fixed port collides with the TIME_WAIT socket left by the previous one.
    """

    def __init__(self, upstream, max_attempts=5):
        # The handler holds its collaborators as class attributes, so these are
        # reset per case rather than per instance.
        throttle.Handler.bucket = throttle.TokenBucket(rps=1000, burst=1000)
        throttle.Handler.stats = throttle.Stats()
        throttle.Handler.upstream = upstream
        throttle.Handler.max_attempts = max_attempts
        throttle.Handler.max_backoff = 0.05
        throttle.Handler.verbose = False

        class Server(throttle.ThreadingHTTPServer):
            daemon_threads = True
            address_family = socket.AF_INET

        self.server = Server(("127.0.0.1", 0), throttle.Handler)
        self.port = self.server.server_address[1]
        self.stats = throttle.Handler.stats
        threading.Thread(
            target=self.server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True
        ).start()

    def request(self, path, method="GET", data=None, headers=None):
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=data,
            method=method,
            headers=headers or {},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            # A 4xx/5xx is a result here, not a failure - several cases assert on
            # exactly which one reaches the caller.
            return exc.code, exc.read()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()


CASES = []


def case(description):
    def register(fn):
        CASES.append((description, fn))
        return fn

    return register


# ---------------------------------------------------------------------------
# Pacing
# ---------------------------------------------------------------------------
@case("the token bucket holds the configured sustained rate")
def test_bucket_paces():
    bucket = throttle.TokenBucket(rps=3.5, burst=8)
    threads = [threading.Thread(target=bucket.take) for _ in range(30)]
    start = time.monotonic()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.monotonic() - start

    # 8 free from the burst, 22 paced at 3.5/s => ~6.3s. Asserted as a band
    # because a shared runner's scheduling adds noise, but a band tight enough
    # that losing the pacing entirely (which would finish instantly) fails.
    assert 5.5 < elapsed < 9.0, f"30 takes at 3.5/s took {elapsed:.2f}s, expected ~6.3s"
    sustained = 22 / elapsed
    assert sustained < 4.0, f"sustained {sustained:.2f}/s exceeds Cloudflare's 4.0/s ceiling"


@case("a burst cannot exceed the bucket size")
def test_burst_bounded():
    bucket = throttle.TokenBucket(rps=100, burst=1)
    start = time.monotonic()
    for _ in range(50):
        bucket.take()
    elapsed = time.monotonic() - start
    assert 0.35 < elapsed < 1.5, f"50 takes at 100/s burst 1 took {elapsed:.2f}s, expected ~0.5s"


# ---------------------------------------------------------------------------
# Forwarding
# ---------------------------------------------------------------------------
@case("the request is forwarded with its credential, body and query intact")
def test_forwarding():
    upstream = FakeUpstream([OK])
    with Proxy(upstream) as proxy:
        status, body = proxy.request(
            "/zones?per_page=50", headers={"Authorization": "Bearer not-a-real-token"}
        )
    call = upstream.calls[0]
    assert status == 200 and body == b'{"success":true}', (status, body)
    assert call["path"] == "/client/v4/zones?per_page=50", call["path"]
    assert call["headers"]["Authorization"] == "Bearer not-a-real-token"
    # Host is rewritten, not forwarded: the inbound one names the loopback
    # listener and Cloudflare's edge routes on Host.
    assert call["headers"]["Host"] == "api.cloudflare.com"
    # Hop-by-hop headers describe the inbound connection and must not cross to
    # the outbound one.
    for name in ("Content-Length", "Connection"):
        assert name not in call["headers"], f"{name} was forwarded"


@case("a path that already carries /client/v4 is not prefixed twice")
def test_prefix_idempotent():
    # Whether the provider's resolved path keeps the base URL's trailing segment
    # depends on whether CLOUDFLARE_BASE_URL ends in a slash. Both spellings have
    # to work, or the deployment breaks on a detail nobody remembers.
    upstream = FakeUpstream([OK])
    with Proxy(upstream) as proxy:
        proxy.request("/client/v4/zones/abc/settings/ssl")
    assert upstream.calls[0]["path"] == "/client/v4/zones/abc/settings/ssl"


@case("the health endpoint is answered locally and spends no budget")
def test_health():
    upstream = FakeUpstream([])
    with Proxy(upstream) as proxy:
        status, body = proxy.request(throttle.HEALTH_PATH)
    assert status == 200 and json.loads(body)["ok"] is True
    # The readiness probe must not consume part of the budget it is checking the
    # guard on, and must not need the upstream to be reachable.
    assert upstream.calls == [], "the health check reached upstream"


# ---------------------------------------------------------------------------
# Retry rules - the part with a blast radius
# ---------------------------------------------------------------------------
@case("a 429 is retried and Retry-After is honoured")
def test_429_retried():
    upstream = FakeUpstream([RATE_LIMITED, RATE_LIMITED, OK])
    with Proxy(upstream) as proxy:
        start = time.monotonic()
        status, _ = proxy.request("/zones")
        elapsed = time.monotonic() - start
        stats = proxy.stats
    assert status == 200, status
    assert len(upstream.calls) == 3, len(upstream.calls)
    # Two waits of at least the 0.01s Retry-After. Without it the backoff floor
    # is 1s, so this also proves the header is preferred over the backoff.
    assert 0.02 <= elapsed < 1.0, f"waited {elapsed:.3f}s, expected the 0.01s Retry-After twice"
    assert stats.throttled_429 == 2 and stats.retries == 2


@case("a 429 on a write is retried, because the write never happened")
def test_429_retried_on_post():
    upstream = FakeUpstream([RATE_LIMITED, OK])
    with Proxy(upstream) as proxy:
        status, _ = proxy.request(
            "/zones", method="POST", data=b'{"name":"x"}',
            headers={"Content-Type": "application/json"},
        )
    assert status == 200 and len(upstream.calls) == 2
    assert upstream.calls[0]["body"] == b'{"name":"x"}'
    assert upstream.calls[1]["body"] == b'{"name":"x"}', "the body was lost on retry"


@case("a 5xx on a write is NOT retried, because the write may have landed")
def test_5xx_not_retried_on_post():
    # The important one. A 502 on a POST is ambiguous - Cloudflare may have
    # created the resource and failed to tell us - so repeating it is how you get
    # two zones. Terraform gets the error and the operator decides.
    upstream = FakeUpstream([BAD_GATEWAY, OK])
    with Proxy(upstream) as proxy:
        status, _ = proxy.request("/zones", method="POST", data=b"{}")
    assert status == 502, status
    assert len(upstream.calls) == 1, f"a POST was repeated after a 5xx ({len(upstream.calls)} calls)"


@case("a 5xx on a read is retried")
def test_5xx_retried_on_get():
    upstream = FakeUpstream([BAD_GATEWAY, OK])
    with Proxy(upstream) as proxy:
        status, _ = proxy.request("/zones")
    assert status == 200 and len(upstream.calls) == 2


@case("a 429 that outlives the retries reaches Terraform as Cloudflare's own 429")
def test_429_passthrough():
    upstream = FakeUpstream([RATE_LIMITED] * 3)
    with Proxy(upstream, max_attempts=3) as proxy:
        status, body = proxy.request("/zones")
    # Passed through rather than rewritten, so the operator sees the rate limit
    # was hit despite the pacing - which means api_rps is set too high.
    assert status == 429, status
    assert json.loads(body)["errors"][0]["code"] == 971


@case("a transport failure is retried and reported in the API's own envelope")
def test_transport_failure():
    upstream = FakeUpstream([ConnectionResetError("reset")] * 3)
    with Proxy(upstream, max_attempts=3) as proxy:
        status, body = proxy.request("/zones")
    payload = json.loads(body)
    assert status == 502, status
    assert len(upstream.calls) == 3, len(upstream.calls)
    # The provider parses the body to build its message, so a limiter failure has
    # to look like an API error or it surfaces as a JSON decode error against an
    # unrelated resource.
    assert payload["success"] is False
    assert "cf-api-throttle" in payload["errors"][0]["message"], payload


def main():
    failures = []
    for description, fn in CASES:
        try:
            fn()
        except AssertionError as exc:
            failures.append((description, str(exc)))
            print(f"FAIL {description}\n     {exc}")
        else:
            print(f"ok   {description}")

    print(f"\n{len(CASES) - len(failures)}/{len(CASES)} passed")
    if failures:
        for description, message in failures:
            print(f"::error::cf-api-throttle: {description} - {message}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
