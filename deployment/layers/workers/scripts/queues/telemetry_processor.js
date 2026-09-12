/**
 * Telemetry ingest and batch writer.
 * NOTE: This .js file is purely an example, showing how a Worker uses the queue
 * and D1 bindings that accounts/<account>/workers.tfvars declares.
 *
 * Two handlers, which is the whole point of the pattern:
 *   fetch() is the producer. It validates an event, puts it on the queue and
 *           returns 202. Nothing the caller waits on touches the database, so a
 *           D1 outage costs a slower write later rather than a failed request
 *           now.
 *   queue() is the consumer. It receives up to batch_size events at once and
 *           writes them in one round trip, which is the difference between one
 *           D1 write per batch and one per request.
 *
 * Bindings (configured via accounts/<account>/workers.tfvars):
 *   TELEMETRY_QUEUE  queue  Producer side. Writes are visible to the consumer
 *                           after the queue's delivery_delay, if any.
 *   TELEMETRY_DB     d1     The database this Worker writes batches into.
 *
 * The consumer side - which queue delivers to this Worker, in what batch size,
 * with how many retries and into which dead letter queue - is declared on the
 * queue in workers.tfvars, not here. A queue has exactly one consumer.
 *
 * The table is created by a migration run from the pipeline, not by Terraform
 * and not by this Worker:
 *
 *   wrangler d1 migrations apply account-a-telemetry --remote
 *
 *   CREATE TABLE IF NOT EXISTS events (
 *     id         TEXT PRIMARY KEY,
 *     occurred   INTEGER NOT NULL,
 *     kind       TEXT NOT NULL,
 *     payload    TEXT NOT NULL
 *   );
 */

const MAX_PAYLOAD_BYTES = 32 * 1024;

/**
 * Rejects anything that should never reach the queue. A message that cannot be
 * written will fail every retry and end up in the dead letter queue, so the
 * cheapest place to catch it is before it is accepted.
 *
 * @param {unknown} event
 * @returns {string | null} the reason it is unusable, or null when it is fine
 */
const rejectionReason = (event) => {
  if (typeof event !== "object" || event === null) {
    return "body must be a JSON object";
  }

  if (typeof event.kind !== "string" || event.kind.length === 0) {
    return "kind must be a non-empty string";
  }

  if (JSON.stringify(event).length > MAX_PAYLOAD_BYTES) {
    return `event is larger than ${MAX_PAYLOAD_BYTES} bytes`;
  }

  return null;
};

/**
 * Writes one batch in a single D1 round trip.
 *
 * @param {D1Database} db
 * @param {Array<{ id: string, event: Record<string, unknown> }>} rows
 */
const writeBatch = async (db, rows) => {
  const insert = db.prepare(
    "INSERT OR IGNORE INTO events (id, occurred, kind, payload) VALUES (?, ?, ?, ?)",
  );

  await db.batch(
    rows.map(({ id, event }) =>
      insert.bind(
        id,
        Number(event.occurred) || Date.now(),
        String(event.kind),
        JSON.stringify(event),
      ),
    ),
  );
};

export default {
  /**
   * Producer: accept an event and return, leaving the write to the consumer.
   *
   * @param {Request} request
   * @param {{ TELEMETRY_QUEUE: Queue, TELEMETRY_DB: D1Database }} env
   */
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    let event;
    try {
      event = await request.json();
    } catch {
      return new Response("body is not JSON", { status: 400 });
    }

    const reason = rejectionReason(event);
    if (reason) {
      return new Response(reason, { status: 400 });
    }

    await env.TELEMETRY_QUEUE.send(event);

    // 202, not 200: the event is durable and not yet stored.
    return new Response(null, { status: 202 });
  },

  /**
   * Consumer: write the batch, and fall back to one statement per message when
   * the batch fails.
   *
   * A queue handler that throws puts the whole batch back, including the
   * messages that were fine, so one permanently broken event would take the
   * other forty-nine with it every time - and eventually dead letter all fifty.
   * Acknowledging message by message keeps the retry to the message that earned
   * it.
   *
   * @param {MessageBatch<Record<string, unknown>>} batch
   * @param {{ TELEMETRY_QUEUE: Queue, TELEMETRY_DB: D1Database }} env
   */
  async queue(batch, env) {
    const rows = batch.messages.map((message) => ({
      id: message.id,
      event: message.body,
    }));

    try {
      await writeBatch(env.TELEMETRY_DB, rows);
      for (const message of batch.messages) {
        message.ack();
      }
      return;
    } catch (error) {
      console.error("batch write failed, retrying message by message", error);
    }

    // INSERT OR IGNORE above keys on the message ID, so a message replayed after
    // a partial failure is stored once rather than twice. At-least-once
    // delivery means the consumer has to be the thing that makes it exactly
    // once.
    for (const message of batch.messages) {
      try {
        await writeBatch(env.TELEMETRY_DB, [
          { id: message.id, event: message.body },
        ]);
        message.ack();
      } catch (error) {
        console.error(`event ${message.id} failed`, error);

        // Explicit rather than implicit: retry() puts this one message back and
        // counts against max_retries, after which the queue's dead letter queue
        // gets it.
        message.retry();
      }
    }
  },
};
