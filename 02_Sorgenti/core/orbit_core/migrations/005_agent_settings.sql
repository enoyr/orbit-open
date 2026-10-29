CREATE TABLE IF NOT EXISTS agent_settings (
    id BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
    instructions TEXT NOT NULL CHECK (length(instructions) <= 20000),
    default_endpoint_id UUID NOT NULL REFERENCES model_endpoints(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO agent_settings (id, name, instructions, default_endpoint_id)
VALUES (
    true,
    'Orbit',
    'Sei Orbit, un assistente personale. Rispondi nella lingua dell’utente con chiarezza e accuratezza. Se non conosci una risposta, dillo apertamente.',
    '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS agent_name TEXT;
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS agent_instructions TEXT;

UPDATE conversations c
SET agent_name = COALESCE(c.agent_name, s.name),
    agent_instructions = COALESCE(c.agent_instructions, s.instructions)
FROM agent_settings s
WHERE s.id = true AND (c.agent_name IS NULL OR c.agent_instructions IS NULL);

ALTER TABLE conversations ALTER COLUMN agent_name SET NOT NULL;
ALTER TABLE conversations ALTER COLUMN agent_instructions SET NOT NULL;
