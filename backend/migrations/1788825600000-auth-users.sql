-- Up Migration
CREATE TABLE monosfer.users (
  id uuid PRIMARY KEY,
  wallet_address text NOT NULL UNIQUE CHECK (wallet_address ~ '^0x[0-9a-f]{40}$'),
  role text NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'courier')),
  display_name varchar(80),
  email varchar(254),
  phone varchar(16),
  courier_profile jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (courier_profile IS NULL OR (jsonb_typeof(courier_profile) = 'object'
    AND courier_profile ? 'vehicleType'
    AND courier_profile - 'vehicleType' = '{}'::jsonb
    AND courier_profile->>'vehicleType' IN ('on_foot', 'bicycle', 'motorcycle', 'car')))
);
CREATE TABLE monosfer.auth_sessions (
  session_hash text PRIMARY KEY CHECK (session_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid NOT NULL REFERENCES monosfer.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (expires_at > created_at)
);
CREATE INDEX auth_sessions_active_user ON monosfer.auth_sessions(user_id) WHERE revoked_at IS NULL;
CREATE INDEX auth_sessions_expiry ON monosfer.auth_sessions(expires_at);

-- Down Migration
-- Intentionally non-destructive: account/session data requires a separate approved rollback.
DO $$ BEGIN RAISE EXCEPTION 'Auth data rollback requires a separately approved migration'; END $$;
