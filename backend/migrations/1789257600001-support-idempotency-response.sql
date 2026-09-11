-- Up Migration
ALTER TABLE monosfer.support_cases ADD COLUMN creation_response jsonb;
-- Preserve existing phase-7 fixture/early rollout cases without copying encrypted notes or request hashes.
UPDATE monosfer.support_cases SET creation_response=jsonb_build_object(
  'id',id,'stream',stream,'delivery_id',delivery_id::text,'status','open','assignee',assignee,
  'created_by',created_by,'created_at',created_at,'updated_at',created_at
);
ALTER TABLE monosfer.support_cases ALTER COLUMN creation_response SET NOT NULL;
ALTER TABLE monosfer.support_cases ALTER COLUMN creation_response SET DEFAULT '{}';

-- Down Migration
DO $$ BEGIN RAISE EXCEPTION 'Support idempotency rollback requires a separately approved migration'; END $$;
