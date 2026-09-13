-- Up Migration
CREATE TABLE monosfer.evidence_packages (
  id uuid PRIMARY KEY,
  scope_hash text NOT NULL UNIQUE CHECK (scope_hash ~ '^[0-9a-f]{64}$'),
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  stream text NOT NULL,
  delivery_id numeric(78,0) NOT NULL,
  private_record_id uuid NOT NULL REFERENCES monosfer.private_delivery_records(id),
  binding text NOT NULL CHECK (binding ~ '^[0-9a-f]{64}$'),
  submitter text NOT NULL CHECK (submitter ~ '^0x[0-9a-f]{40}$'),
  content_type text NOT NULL CHECK (content_type IN ('text/plain','image/png','image/jpeg')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ready','failed')),
  ciphertext_hash text NOT NULL CHECK (ciphertext_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX evidence_owner ON monosfer.evidence_packages(submitter,created_at);
CREATE TABLE monosfer.provider_jobs (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('evidence.store','notification.send')),
  stream text NOT NULL,
  dedup_key text NOT NULL UNIQUE,
  evidence_id uuid REFERENCES monosfer.evidence_packages(id),
  encrypted_payload jsonb NOT NULL CHECK (jsonb_typeof(encrypted_payload)='object'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','done','failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text CHECK (last_error='PROVIDER_UNAVAILABLE'),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
CREATE INDEX provider_jobs_due ON monosfer.provider_jobs(next_attempt_at,created_at) WHERE status='pending';
CREATE TABLE monosfer.notifications (
  id uuid PRIMARY KEY REFERENCES monosfer.provider_jobs(id),
  wallet text NOT NULL CHECK (wallet ~ '^0x[0-9a-f]{40}$'),
  stream text NOT NULL,
  delivery_id numeric(78,0) NOT NULL,
  binding text NOT NULL,
  template text NOT NULL CHECK (template IN ('delivery_state','evidence_ready')),
  arguments jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notification_wallet ON monosfer.notifications(wallet,created_at,id);
CREATE TABLE monosfer.notification_cursors (
  stream text NOT NULL,
  delivery_id numeric(78,0) NOT NULL,
  state text NOT NULL,
  courier text NOT NULL,
  quote_digest text NOT NULL,
  PRIMARY KEY(stream,delivery_id)
);

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Evidence/provider rollback requires a separately approved migration'; END $$;
