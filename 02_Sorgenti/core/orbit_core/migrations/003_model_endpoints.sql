CREATE TABLE IF NOT EXISTS model_endpoints (
    id UUID PRIMARY KEY,
    label TEXT NOT NULL,
    provider TEXT NOT NULL CHECK (provider IN ('demo', 'openai', 'ollama')),
    model_name TEXT NOT NULL,
    base_url TEXT,
    is_local BOOLEAN NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO model_endpoints (id, label, provider, model_name, is_local)
VALUES ('00000000-0000-0000-0000-000000000001', 'Demo locale (senza IA)', 'demo', 'demo', true)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS endpoint_id UUID REFERENCES model_endpoints(id);

UPDATE conversations
SET endpoint_id = '00000000-0000-0000-0000-000000000001'
WHERE endpoint_id IS NULL;

ALTER TABLE conversations ALTER COLUMN endpoint_id SET NOT NULL;
ALTER TABLE conversations ALTER COLUMN endpoint_id SET DEFAULT '00000000-0000-0000-0000-000000000001';
