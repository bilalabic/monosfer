-- Up Migration
CREATE TABLE monosfer.support_cases (
  id uuid PRIMARY KEY,
  stream text NOT NULL,
  delivery_id numeric(78,0) NOT NULL CHECK(delivery_id>=0),
  status text NOT NULL CHECK(status IN ('open','investigating','closed')) DEFAULT 'open',
  assignee text CHECK(assignee ~ '^0x[0-9a-f]{40}$'),
  created_by text NOT NULL CHECK(created_by ~ '^0x[0-9a-f]{40}$'),
  scope_hash text NOT NULL CHECK(scope_hash ~ '^[0-9a-f]{64}$'),
  request_hash text NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
  idempotency_expires_at timestamptz NOT NULL,
  encrypted_note jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_case_page ON monosfer.support_cases(id);
CREATE INDEX support_case_scope ON monosfer.support_cases(scope_hash, idempotency_expires_at);
CREATE INDEX support_case_access ON monosfer.support_cases(stream,delivery_id,assignee) WHERE status IN ('open','investigating');
CREATE TABLE monosfer.support_case_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  case_id uuid NOT NULL REFERENCES monosfer.support_cases(id),
  actor_wallet text NOT NULL CHECK(actor_wallet ~ '^0x[0-9a-f]{40}$'),
  action text NOT NULL CHECK(action IN ('created','updated')),
  status text NOT NULL CHECK(status IN ('open','investigating','closed')),
  assignee text CHECK(assignee ~ '^0x[0-9a-f]{40}$'),
  encrypted_note jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE monosfer.privileged_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL,
  actor_wallet text CHECK(actor_wallet ~ '^0x[0-9a-f]{40}$'),
  action text NOT NULL CHECK(action IN ('support.delivery','support.private','support.evidence','support.content','support.case.create','support.case.list','support.case.read','support.case.update','support.reputation','admin.audit','ops.traces','privileged.guard')),
  target_type text NOT NULL CHECK(target_type IN ('delivery','evidence','case','wallet','audit','trace','route')),
  target_id text NOT NULL CHECK(length(target_id)<=128),
  decision text NOT NULL CHECK(decision IN ('allowed','denied','failed')),
  reason_code text NOT NULL CHECK(reason_code IN ('AUTHORIZED','ACCESS_DENIED','UNAUTHENTICATED','UNAVAILABLE','INVALID_REQUEST','CONFLICT','NOT_FOUND')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_page ON monosfer.privileged_audit_log(id);
CREATE INDEX audit_request ON monosfer.privileged_audit_log(request_id);
CREATE FUNCTION monosfer.reject_append_only_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Append-only record'; END $$;
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON monosfer.privileged_audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION monosfer.reject_append_only_mutation();
CREATE TRIGGER case_events_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON monosfer.support_case_events
  FOR EACH STATEMENT EXECUTE FUNCTION monosfer.reject_append_only_mutation();
CREATE TABLE monosfer.reputation_projections (
  stream text NOT NULL,
  wallet text NOT NULL CHECK(wallet ~ '^0x[0-9a-f]{40}$'),
  counters jsonb NOT NULL CHECK(jsonb_typeof(counters)='object'),
  source_block bigint NOT NULL,
  source_hash text NOT NULL,
  export_fingerprint text NOT NULL,
  rebuilt_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(stream,wallet)
);
CREATE TABLE monosfer.referral_reward_projections (
  stream text NOT NULL,
  wallet text NOT NULL CHECK(wallet ~ '^0x[0-9a-f]{40}$'),
  status text NOT NULL CHECK(status='pending_policy'),
  source_block bigint NOT NULL,
  source_hash text NOT NULL,
  export_fingerprint text NOT NULL,
  PRIMARY KEY(stream,wallet)
);
CREATE TABLE monosfer.ops_trace_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL,
  event text NOT NULL CHECK(event='http_response'),
  status_code integer NOT NULL CHECK(status_code BETWEEN 100 AND 599),
  duration_ms integer NOT NULL CHECK(duration_ms>=0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX trace_request ON monosfer.ops_trace_events(request_id,id);
CREATE TABLE monosfer.ops_drill_runs (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK(kind IN ('projection_rebuild','restore_fixture')),
  stream text,
  status text NOT NULL CHECK(status IN ('passed','failed')),
  duration_ms integer NOT NULL CHECK(duration_ms>=0),
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Audit/operations rollback requires a separately approved migration'; END $$;
