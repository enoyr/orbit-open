ALTER TABLE conversations
ADD COLUMN access_mode TEXT NOT NULL DEFAULT 'approval_required'
CHECK (access_mode IN ('approval_required', 'full_access'));
