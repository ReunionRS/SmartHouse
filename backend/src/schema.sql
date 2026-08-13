DROP TABLE IF EXISTS maintenance_request_notification_hidden CASCADE;
DROP TABLE IF EXISTS maintenance_notification_hidden CASCADE;
DROP TABLE IF EXISTS support_message_notification_hidden CASCADE;
DROP TABLE IF EXISTS stage_comment_notification_hidden CASCADE;
DROP TABLE IF EXISTS stage_comment_notifications CASCADE;
DROP TABLE IF EXISTS maintenance_requests CASCADE;
DROP TABLE IF EXISTS maintenance_tasks CASCADE;
DROP TABLE IF EXISTS finance_expenses CASCADE;
DROP TABLE IF EXISTS journal_entries CASCADE;
DROP TABLE IF EXISTS support_messages CASCADE;
DROP TABLE IF EXISTS documents CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS user_push_tokens CASCADE;

-- Предыдущая версия хранила HA-токены открытым текстом. Таблица удаляется только при
-- обнаружении старой колонки; новая зашифрованная схема переживает перезапуски.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'home_assistant_connections' AND column_name = 'access_token'
  ) THEN
    DROP TABLE home_assistant_connections CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  fio TEXT NOT NULL DEFAULT '',
  avatar_url TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users DROP COLUMN IF EXISTS role;
ALTER TABLE users DROP COLUMN IF EXISTS is_active;
ALTER TABLE users DROP COLUMN IF EXISTS is_archived;
ALTER TABLE users DROP COLUMN IF EXISTS two_factor_enabled;
ALTER TABLE users DROP COLUMN IF EXISTS two_factor_secret;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE users ALTER COLUMN fio SET DEFAULT '';
ALTER TABLE users ALTER COLUMN avatar_url SET DEFAULT '';
UPDATE users SET fio = '' WHERE fio IS NULL;
UPDATE users SET avatar_url = '' WHERE avatar_url IS NULL;
ALTER TABLE users ALTER COLUMN fio SET NOT NULL;
ALTER TABLE users ALTER COLUMN avatar_url SET NOT NULL;

CREATE TABLE IF NOT EXISTS home_assistant_connections (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  house_id TEXT,
  base_url TEXT NOT NULL,
  access_token_encrypted TEXT NOT NULL,
  refresh_token_encrypted TEXT NOT NULL,
  client_id TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'connected',
  last_checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS push_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  token_type TEXT NOT NULL DEFAULT 'fcm',
  platform TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  locale TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens(user_id);

CREATE TABLE IF NOT EXISTS ha_pairing_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hub_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ha_pairing_sessions_lookup
  ON ha_pairing_sessions (hub_id, token_hash)
  WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS ha_one_time_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ha_one_time_tokens_lookup
  ON ha_one_time_tokens (token_hash)
  WHERE consumed_at IS NULL;
