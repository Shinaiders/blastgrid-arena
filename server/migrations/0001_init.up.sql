-- 0001_init: esquema inicial (docs/DATABASE.md §3–4).
-- Cada migration roda numa transação aberta pelo runner (internal/persistence).

CREATE TABLE users (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email          text NULL CHECK (email IS NULL OR char_length(email) BETWEEN 3 AND 254),
    password_hash  text NULL CHECK (password_hash IS NULL OR char_length(password_hash) <= 255),
    steam_id       bigint NULL,
    kind           text NOT NULL DEFAULT 'registered' CHECK (kind IN ('registered', 'guest')),
    status         text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'banned', 'deleted')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    last_login_at  timestamptz NULL,
    -- conta registrada precisa de email; convidado não tem credenciais
    CHECK (kind <> 'guest' OR (email IS NULL AND password_hash IS NULL))
);
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email)) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX users_steam_id_key ON users (steam_id) WHERE steam_id IS NOT NULL;

-- Catálogo (ids estáveis em text, iguais aos do cliente e do protocolo).
CREATE TABLE characters (
    id          text PRIMARY KEY CHECK (id ~ '^[a-z0-9_]{1,32}$'),
    name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    base_speed  integer NOT NULL CHECK (base_speed > 0),   -- militiles/tick
    base_bombs  integer NOT NULL CHECK (base_bombs > 0),
    base_range  integer NOT NULL CHECK (base_range > 0),
    enabled     boolean NOT NULL DEFAULT true
);

CREATE TABLE skins (
    id            text PRIMARY KEY CHECK (id ~ '^[a-z0-9_]{1,32}$'),
    character_id  text NOT NULL REFERENCES characters (id),
    name          text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    rarity        text NOT NULL DEFAULT 'common' CHECK (rarity IN ('common', 'rare', 'epic', 'legendary')),
    enabled       boolean NOT NULL DEFAULT true
);
CREATE INDEX skins_character_id_idx ON skins (character_id);

CREATE TABLE user_profiles (
    user_id             bigint PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    display_name        text NOT NULL CHECK (char_length(display_name) BETWEEN 3 AND 20),
    avatar              text NULL CHECK (avatar IS NULL OR char_length(avatar) <= 32),
    selected_character  text NOT NULL DEFAULT 'sparky_a' REFERENCES characters (id),
    selected_skin       text NULL REFERENCES skins (id),
    country             text NULL CHECK (country IS NULL OR country ~ '^[A-Z]{2}$'),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX user_profiles_display_name_lower_key ON user_profiles (lower(display_name));

CREATE TABLE player_inventory (
    user_id      bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    item_kind    text NOT NULL CHECK (item_kind IN ('character', 'skin')),
    item_id      text NOT NULL,
    acquired_at  timestamptz NOT NULL DEFAULT now(),
    source       text NOT NULL DEFAULT 'default' CHECK (source IN ('default', 'achievement', 'event', 'admin')),
    PRIMARY KEY (user_id, item_kind, item_id)
);

CREATE TABLE matches (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mode            text NOT NULL CHECK (mode IN ('ffa', 'team', 'lms', 'practice')),
    seed            bigint NOT NULL CHECK (seed BETWEEN 0 AND 4294967295),  -- u32
    tick_rate       smallint NOT NULL CHECK (tick_rate BETWEEN 10 AND 60),
    started_at      timestamptz NOT NULL,
    ended_at        timestamptz NOT NULL,
    duration_ticks  integer NOT NULL CHECK (duration_ticks >= 0),
    end_reason      text NOT NULL CHECK (end_reason IN ('last_alive', 'time_up', 'draw', 'aborted')),
    winner_user_id  bigint NULL REFERENCES users (id) ON DELETE SET NULL,
    server_version  text NOT NULL CHECK (char_length(server_version) <= 64),
    CHECK (ended_at >= started_at)
);
CREATE INDEX matches_ended_at_idx ON matches (ended_at DESC);

CREATE TABLE match_players (
    match_id       bigint NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
    slot           smallint NOT NULL CHECK (slot BETWEEN 0 AND 7),     -- até 8 jogadores
    user_id        bigint NULL REFERENCES users (id) ON DELETE SET NULL,
    place          smallint NOT NULL CHECK (place BETWEEN 1 AND 8),
    score          integer NOT NULL DEFAULT 0,
    kills          smallint NOT NULL DEFAULT 0 CHECK (kills >= 0),
    deaths         smallint NOT NULL DEFAULT 0 CHECK (deaths >= 0),
    blocks         smallint NOT NULL DEFAULT 0 CHECK (blocks >= 0),
    powerups       smallint NOT NULL DEFAULT 0 CHECK (powerups >= 0),
    platform       text NOT NULL CHECK (platform IN ('web', 'windows', 'linux', 'macos')),
    disconnected   boolean NOT NULL DEFAULT false,
    rating_before  integer NULL,
    rating_after   integer NULL,
    PRIMARY KEY (match_id, slot)
);
CREATE INDEX match_players_user_history_idx ON match_players (user_id, match_id DESC) WHERE user_id IS NOT NULL;

CREATE TABLE player_statistics (
    user_id             bigint PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    matches_played      integer NOT NULL DEFAULT 0 CHECK (matches_played >= 0),
    wins                integer NOT NULL DEFAULT 0 CHECK (wins >= 0),
    draws               integer NOT NULL DEFAULT 0 CHECK (draws >= 0),
    kills               integer NOT NULL DEFAULT 0 CHECK (kills >= 0),
    deaths              integer NOT NULL DEFAULT 0 CHECK (deaths >= 0),
    blocks_destroyed    integer NOT NULL DEFAULT 0 CHECK (blocks_destroyed >= 0),
    powerups_collected  integer NOT NULL DEFAULT 0 CHECK (powerups_collected >= 0),
    best_score          integer NOT NULL DEFAULT 0,
    total_score         bigint NOT NULL DEFAULT 0,
    play_time_ticks     bigint NOT NULL DEFAULT 0 CHECK (play_time_ticks >= 0),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE rankings (
    season      smallint NOT NULL CHECK (season >= 1),
    mode        text NOT NULL CHECK (mode IN ('ffa', 'team', 'lms')),
    user_id     bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    rating      integer NOT NULL DEFAULT 1000,
    matches     integer NOT NULL DEFAULT 0 CHECK (matches >= 0),
    wins        integer NOT NULL DEFAULT 0 CHECK (wins >= 0),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (season, mode, user_id)
);
-- Top N e paginação keyset: WHERE season=$1 AND mode=$2 AND (rating, user_id) < ($3, $4)
-- ORDER BY rating DESC, user_id DESC. Também serve o COUNT da posição (index-only scan).
CREATE INDEX rankings_leaderboard_idx ON rankings (season, mode, rating DESC, user_id DESC);

CREATE TABLE achievements (
    id           text PRIMARY KEY CHECK (id ~ '^[a-z0-9_]{1,48}$'),   -- mesmo id da conquista Steam (Fase 6)
    name         text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    description  text NOT NULL CHECK (char_length(description) <= 200),
    hidden       boolean NOT NULL DEFAULT false
);

CREATE TABLE player_achievements (
    user_id         bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    achievement_id  text NOT NULL REFERENCES achievements (id),
    progress        integer NOT NULL DEFAULT 0 CHECK (progress >= 0),
    unlocked_at     timestamptz NULL,
    PRIMARY KEY (user_id, achievement_id)
);

-- Seed do catálogo (GDD §2 e §4–5: robôs-mascote "Sparkies"; stats iguais na v1:
-- velocidade 4,0 tiles/s = 200 militiles/tick a 20 Hz, 1 bomba, alcance 2).
INSERT INTO characters (id, name, base_speed, base_bombs, base_range) VALUES
    ('sparky_a', 'Volt',   200, 1, 2),
    ('sparky_b', 'Ember',  200, 1, 2),
    ('sparky_c', 'Moss',   200, 1, 2),
    ('sparky_d', 'Frost',  200, 1, 2);

INSERT INTO skins (id, character_id, name, rarity) VALUES
    ('sparky_a_default', 'sparky_a', 'Volt Classic',  'common'),
    ('sparky_b_default', 'sparky_b', 'Ember Classic', 'common'),
    ('sparky_c_default', 'sparky_c', 'Moss Classic',  'common'),
    ('sparky_d_default', 'sparky_d', 'Frost Classic', 'common');

INSERT INTO achievements (id, name, description) VALUES
    ('first_win',      'Primeira vitória',  'Venceu uma partida online.'),
    ('chain_reaction', 'Efeito dominó',     'Detonou 3 bombas em uma única reação em cadeia.'),
    ('collector',      'Colecionador',      'Coletou 100 power-ups no total.');
