-- Up Migration
CREATE TABLE monosfer.private_data_import_runs (
  id uuid PRIMARY KEY,
  source_namespace varchar(64) NOT NULL CHECK (source_namespace ~ '^[a-zA-Z0-9_-]{1,64}$'),
  mode text NOT NULL CHECK (mode IN ('dry_run', 'apply')),
  mapping_version integer NOT NULL DEFAULT 1 CHECK (mapping_version = 1),
  status text NOT NULL CHECK (status IN ('running', 'completed', 'completed_with_errors', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE monosfer.private_delivery_records (
  id uuid PRIMARY KEY,
  source text NOT NULL DEFAULT 'legacy_mongo' CHECK (source = 'legacy_mongo'),
  verification_status text NOT NULL DEFAULT 'legacy_unverified' CHECK (verification_status = 'legacy_unverified'),
  source_namespace varchar(64) NOT NULL CHECK (source_namespace ~ '^[a-zA-Z0-9_-]{1,64}$'),
  source_collection text NOT NULL CHECK (source_collection IN ('deliveries', 'disputes', 'users')),
  legacy_mongo_id text NOT NULL CHECK (legacy_mongo_id ~ '^[a-f0-9]{24}$'),
  parent_legacy_id text CHECK (parent_legacy_id ~ '^[a-f0-9]{24}$'),
  kind text NOT NULL CHECK (kind IN ('delivery', 'dispute', 'courier_location')),
  customer_wallet text CHECK (customer_wallet ~ '^0x[0-9a-f]{40}$'),
  courier_wallet text CHECK (courier_wallet ~ '^0x[0-9a-f]{40}$'),
  legacy_status text NOT NULL,
  metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata) = 'object'),
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version = 1),
  encrypted_payload jsonb NOT NULL CHECK (jsonb_typeof(encrypted_payload) = 'object'
    AND encrypted_payload ?& ARRAY['alg','keyId','iv','tag','ciphertext','aad']
    AND encrypted_payload - ARRAY['alg','keyId','iv','tag','ciphertext','aad'] = '{}'::jsonb
    AND encrypted_payload->>'alg' = 'AES-256-GCM'),
  import_run_id uuid NOT NULL REFERENCES monosfer.private_data_import_runs(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_namespace, source_collection, legacy_mongo_id),
  CHECK ((kind = 'delivery' AND source_collection = 'deliveries' AND customer_wallet IS NOT NULL AND parent_legacy_id IS NULL
    AND legacy_status IN ('OpenForBids','Accepted','InTransit','Delivered','Cancelled'))
    OR (kind = 'dispute' AND source_collection = 'disputes' AND parent_legacy_id IS NOT NULL AND customer_wallet IS NOT NULL
    AND legacy_status IN ('open','evidence_collection','jury_assigned','voting','resolved','cancelled'))
    OR (kind = 'courier_location' AND source_collection = 'users' AND courier_wallet IS NOT NULL AND legacy_status = 'archived'))
);
CREATE INDEX private_records_customer ON monosfer.private_delivery_records(customer_wallet, legacy_status);
CREATE INDEX private_records_courier ON monosfer.private_delivery_records(courier_wallet, legacy_status);
CREATE INDEX private_records_parent ON monosfer.private_delivery_records(source_namespace, parent_legacy_id) WHERE parent_legacy_id IS NOT NULL;
CREATE TABLE monosfer.private_data_import_items (
  run_id uuid NOT NULL REFERENCES monosfer.private_data_import_runs(id),
  source_collection text NOT NULL CHECK (source_collection IN ('deliveries', 'disputes', 'users')),
  source_key text NOT NULL CHECK (source_key ~ '^[a-f0-9]{64}$'),
  legacy_mongo_id text CHECK (legacy_mongo_id ~ '^[a-f0-9]{24}$'),
  status text NOT NULL CHECK (status IN ('pending', 'validated', 'imported', 'skipped_existing', 'skipped_no_private', 'invalid', 'failed')),
  reason_code text CHECK (reason_code IN ('INVALID_ID','INVALID_WALLET','INVALID_PAYLOAD','INVALID_STATUS','MISSING_PARENT','IMPORT_FAILED')),
  record_id uuid REFERENCES monosfer.private_delivery_records(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, source_collection, source_key)
);
CREATE INDEX private_import_items_status ON monosfer.private_data_import_items(run_id, status);

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Private data rollback requires a separately approved migration'; END $$;
