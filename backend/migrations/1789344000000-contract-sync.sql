-- Up Migration
ALTER TABLE monosfer.indexer_blocks ADD COLUMN timestamp bigint CHECK (timestamp >= 0);
-- Historical timestamps cannot be fabricated. Such streams require reviewed reindexing.
UPDATE monosfer.indexer_streams SET status='error',integrity_ok=false,checked_at=NULL
WHERE EXISTS (SELECT 1 FROM monosfer.indexer_blocks b WHERE b.stream=indexer_streams.stream AND b.timestamp IS NULL);
CREATE TABLE monosfer.proof_issuances (
  scope_hash text PRIMARY KEY,
  request_hash text NOT NULL,
  stream text NOT NULL REFERENCES monosfer.indexer_streams(stream),
  delivery_id numeric(78,0) NOT NULL,
  actor text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('pickup','return','pod')),
  encrypted_response jsonb NOT NULL,
  expires_at timestamptz NOT NULL,
  idempotency_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE monosfer.dispute_event_inbox (
  stream text NOT NULL,
  block_hash text NOT NULL,
  block_number bigint NOT NULL,
  log_index integer NOT NULL,
  transaction_index integer NOT NULL,
  dispute_id numeric(78,0),
  event_name text NOT NULL,
  args jsonb NOT NULL,
  canonical boolean NOT NULL,
  PRIMARY KEY(stream,block_hash,log_index),
  FOREIGN KEY(stream,block_hash) REFERENCES monosfer.indexer_blocks(stream,hash)
);
CREATE TABLE monosfer.dispute_projections (
  stream text NOT NULL REFERENCES monosfer.indexer_streams(stream),
  dispute_id numeric(78,0) NOT NULL,
  delivery_id numeric(78,0) NOT NULL,
  data jsonb NOT NULL,
  updated_block bigint NOT NULL,
  PRIMARY KEY(stream,dispute_id)
);
CREATE INDEX dispute_delivery ON monosfer.dispute_projections(stream,delivery_id);
-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Contract sync rollback requires a separately approved migration'; END $$;
