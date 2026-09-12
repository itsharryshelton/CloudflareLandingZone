-- Schema for the `telemetry` D1 database, written by the queue consumer in
-- scripts/queues/telemetry_processor.js.
--
-- `id` is the queue message ID rather than a generated key, which is what makes
-- the consumer's INSERT OR IGNORE idempotent: Queues delivers at least once, so
-- a batch that failed halfway is redelivered and the rows that already landed
-- must not land twice.

CREATE TABLE IF NOT EXISTS events (
  id       TEXT PRIMARY KEY,
  occurred INTEGER NOT NULL,
  kind     TEXT NOT NULL,
  payload  TEXT NOT NULL
);

-- Reads are "what happened, of this kind, in this window". Without the index
-- that is a full scan of every row ever written, and D1 charges for rows read.
CREATE INDEX IF NOT EXISTS events_kind_occurred ON events (kind, occurred);
