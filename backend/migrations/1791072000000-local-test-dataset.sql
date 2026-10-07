-- Up Migration
-- Public, synthetic fixture labels only; lifecycle state comes from the indexer.
CREATE TABLE monosfer.development_datasets (
  stream text PRIMARY KEY,
  data jsonb NOT NULL CHECK (jsonb_typeof(data) = 'object'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Down Migration
DROP TABLE monosfer.development_datasets;
