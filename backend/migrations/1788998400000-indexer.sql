-- Up Migration
CREATE TABLE monosfer.indexer_streams (
  stream text PRIMARY KEY,
  chain_id integer NOT NULL CHECK (chain_id > 0),
  contract_address text NOT NULL CHECK (contract_address ~ '^0x[0-9a-f]{40}$'),
  export_fingerprint text NOT NULL CHECK (export_fingerprint ~ '^[0-9a-f]{64}$'),
  start_block bigint NOT NULL CHECK (start_block > 0),
  last_block bigint NOT NULL,
  last_hash text NOT NULL CHECK (last_hash ~ '^0x[0-9a-f]{64}$'),
  observed_head bigint NOT NULL,
  status text NOT NULL CHECK (status IN ('syncing','ready','error','replaying','reconciling')),
  checked_at timestamptz,
  reconciled_at timestamptz,
  integrity_ok boolean NOT NULL DEFAULT true,
  CHECK (last_block >= start_block - 1),
  UNIQUE (chain_id, contract_address)
);
CREATE TABLE monosfer.indexer_blocks (
  stream text NOT NULL REFERENCES monosfer.indexer_streams(stream),
  number bigint NOT NULL CHECK (number >= 0),
  hash text NOT NULL CHECK (hash ~ '^0x[0-9a-f]{64}$'),
  parent_hash text NOT NULL CHECK (parent_hash ~ '^0x[0-9a-f]{64}$'),
  canonical boolean NOT NULL,
  PRIMARY KEY (stream, hash)
);
CREATE UNIQUE INDEX indexer_canonical_height ON monosfer.indexer_blocks(stream, number) WHERE canonical;
CREATE TABLE monosfer.chain_event_inbox (
  stream text NOT NULL,
  block_hash text NOT NULL,
  block_number bigint NOT NULL,
  transaction_hash text NOT NULL CHECK (transaction_hash ~ '^0x[0-9a-f]{64}$'),
  transaction_index integer NOT NULL CHECK (transaction_index >= 0),
  log_index integer NOT NULL CHECK (log_index >= 0),
  event_name text NOT NULL,
  delivery_id numeric(78,0),
  args jsonb NOT NULL,
  raw_log jsonb NOT NULL,
  canonical boolean NOT NULL,
  PRIMARY KEY (stream, block_hash, log_index),
  FOREIGN KEY (stream, block_hash) REFERENCES monosfer.indexer_blocks(stream, hash)
);
CREATE UNIQUE INDEX inbox_canonical_transaction ON monosfer.chain_event_inbox(stream, transaction_hash, log_index) WHERE canonical;
CREATE INDEX inbox_replay ON monosfer.chain_event_inbox(stream, delivery_id, block_number, transaction_index, log_index) WHERE canonical;
CREATE TABLE monosfer.delivery_projections (
  stream text NOT NULL REFERENCES monosfer.indexer_streams(stream),
  delivery_id numeric(78,0) NOT NULL CHECK (delivery_id >= 0),
  data jsonb NOT NULL,
  updated_block bigint NOT NULL,
  PRIMARY KEY (stream, delivery_id)
);
CREATE TABLE monosfer.bid_projections (
  stream text NOT NULL,
  delivery_id numeric(78,0) NOT NULL,
  courier text NOT NULL CHECK (courier ~ '^0x[0-9a-f]{40}$'),
  data jsonb NOT NULL,
  PRIMARY KEY (stream, delivery_id, courier),
  FOREIGN KEY (stream, delivery_id) REFERENCES monosfer.delivery_projections(stream, delivery_id)
);
-- No HTTP writer. Phase 5 must derive this binding from server-issued signed quote provenance.
CREATE TABLE monosfer.private_delivery_links (
  private_record_id uuid PRIMARY KEY REFERENCES monosfer.private_delivery_records(id),
  stream text NOT NULL REFERENCES monosfer.indexer_streams(stream),
  delivery_id numeric(78,0) NOT NULL,
  quote_digest text NOT NULL CHECK (quote_digest ~ '^0x[0-9a-f]{64}$'),
  UNIQUE (stream, delivery_id)
);

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Indexer rollback requires a separately approved migration'; END $$;
