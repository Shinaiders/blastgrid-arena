-- 0002_auth_sessions: sessões de autenticação e refresh tokens (docs/DATABASE.md §3).
-- O token de renovação nunca é salvo em texto puro, apenas seu hash SHA-256 (32 bytes).

CREATE TABLE auth_sessions (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    refresh_token_hash  bytea NOT NULL CHECK (octet_length(refresh_token_hash) = 32),
    user_agent          text NULL CHECK (user_agent IS NULL OR char_length(user_agent) <= 255),
    platform            text NOT NULL CHECK (platform IN ('web', 'windows', 'linux', 'macos')),
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,
    revoked_at          timestamptz NULL,
    CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX auth_sessions_token_hash_key ON auth_sessions (refresh_token_hash);
CREATE INDEX auth_sessions_user_id_idx ON auth_sessions (user_id, expires_at DESC);
