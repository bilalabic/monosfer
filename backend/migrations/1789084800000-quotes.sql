-- Up Migration
ALTER TABLE monosfer.private_delivery_records
  DROP CONSTRAINT private_delivery_records_source_check,
  DROP CONSTRAINT private_delivery_records_verification_status_check,
  DROP CONSTRAINT private_delivery_records_check,
  ALTER COLUMN legacy_mongo_id DROP NOT NULL,
  ALTER COLUMN import_run_id DROP NOT NULL;
ALTER TABLE monosfer.private_delivery_records ADD CONSTRAINT private_record_provenance CHECK (
  (source='legacy_mongo' AND verification_status='legacy_unverified' AND legacy_mongo_id IS NOT NULL AND import_run_id IS NOT NULL
    AND ((kind='delivery' AND source_collection='deliveries' AND customer_wallet IS NOT NULL AND parent_legacy_id IS NULL
      AND legacy_status IN ('OpenForBids','Accepted','InTransit','Delivered','Cancelled'))
    OR (kind='dispute' AND source_collection='disputes' AND parent_legacy_id IS NOT NULL AND customer_wallet IS NOT NULL
      AND legacy_status IN ('open','evidence_collection','jury_assigned','voting','resolved','cancelled'))
    OR (kind='courier_location' AND source_collection='users' AND courier_wallet IS NOT NULL AND legacy_status='archived')))
  OR (source='quote_api' AND verification_status='pending_chain' AND kind='delivery' AND source_collection='deliveries'
    AND source_namespace='quote-api-v1' AND customer_wallet IS NOT NULL AND courier_wallet IS NULL
    AND legacy_mongo_id IS NULL AND import_run_id IS NULL AND parent_legacy_id IS NULL AND legacy_status='quote_pending')
);
CREATE TABLE monosfer.risk_quote_issuances (
  digest text PRIMARY KEY CHECK (digest ~ '^0x[0-9a-f]{64}$'),
  private_record_id uuid NOT NULL REFERENCES monosfer.private_delivery_records(id),
  customer text NOT NULL CHECK (customer ~ '^0x[0-9a-f]{40}$'),
  stream text NOT NULL,
  export_fingerprint text NOT NULL CHECK (export_fingerprint ~ '^[0-9a-f]{64}$'),
  quote_bundle_fingerprint text NOT NULL CHECK (quote_bundle_fingerprint ~ '^[0-9a-f]{64}$'),
  signer text NOT NULL CHECK (signer ~ '^0x[0-9a-f]{40}$'),
  quote jsonb NOT NULL CHECK (jsonb_typeof(quote)='object'),
  expires_at timestamptz NOT NULL,
  issued_block bigint NOT NULL,
  refreshed_from text UNIQUE REFERENCES monosfer.risk_quote_issuances(digest),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX quote_record_history ON monosfer.risk_quote_issuances(private_record_id);
CREATE INDEX quote_owner ON monosfer.risk_quote_issuances(customer, created_at);
CREATE TABLE monosfer.risk_quote_inputs (
  quote_digest text PRIMARY KEY REFERENCES monosfer.risk_quote_issuances(digest),
  public_input jsonb NOT NULL,
  policy_version text NOT NULL,
  policy_snapshot jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE monosfer.idempotency_keys (
  scope_hash text PRIMARY KEY CHECK (scope_hash ~ '^[0-9a-f]{64}$'),
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  quote_digest text NOT NULL REFERENCES monosfer.risk_quote_issuances(digest),
  encrypted_response jsonb NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE monosfer.transactional_outbox (
  id uuid PRIMARY KEY,
  topic text NOT NULL CHECK (topic='quote.link'),
  quote_digest text NOT NULL UNIQUE REFERENCES monosfer.risk_quote_issuances(digest),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_due ON monosfer.transactional_outbox(next_attempt_at, created_at) WHERE status='pending';
CREATE INDEX projection_quote_digest ON monosfer.delivery_projections(stream, (data->>'quoteDigest'));

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Quote rollback requires a separately approved migration'; END $$;
