ALTER TABLE model_endpoints DROP CONSTRAINT IF EXISTS model_endpoints_provider_check;
ALTER TABLE model_endpoints ADD CONSTRAINT model_endpoints_provider_check
CHECK (provider IN ('demo', 'openai', 'anthropic', 'ollama', 'openai_compatible', 'chatgpt_plan'));
