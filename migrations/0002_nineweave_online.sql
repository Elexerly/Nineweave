-- Nineweave online play: anonymous device-token players, lobby rooms with an
-- authoritative rules snapshot, and an append-only match result log.
-- No PII beyond an optional screen name; every secret is stored hashed.

create table if not exists nw_players (
  id              text primary key,            -- public player id ("p_…")
  token_hash      text not null unique,        -- sha256 of the device token
  screen_name     text,                        -- optional until chosen
  apple_sub       text unique,                 -- reserved: future Sign in with Apple subject
  purchases       jsonb not null default '[]'::jsonb,
  unlocks         jsonb not null default '[]'::jsonb,
  last_hero_id    text,
  matches_won     integer not null default 0,  -- official score
  matches_lost    integer not null default 0,
  matches_played  integer not null default 0,  -- wins + losses + draws
  boards_won      integer not null default 0,  -- internal: small boards claimed
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  last_seen_at    timestamptz not null default now()
);

-- Screen names are unique case-insensitively.
create unique index if not exists nw_players_screen_name_lower
  on nw_players (lower(screen_name)) where screen_name is not null;

-- Leaderboard: named players who have finished at least one match.
create index if not exists nw_players_leaderboard
  on nw_players (matches_won desc, matches_played asc, created_at asc)
  where screen_name is not null and matches_played > 0;

-- One row per room. Slot "a" is the host, "b" the guest; x_slot says which
-- slot currently holds seat 1 (X). Seats swap on every rematch.
create table if not exists nw_rooms (
  id               text primary key,
  code             text not null,               -- five uppercase letters/digits
  status           text not null check (status in ('waiting', 'active', 'finished', 'closed')),
  is_private       boolean not null default false,
  password_hash    text,                        -- scrypt; null for public rooms
  round            integer not null default 1,
  x_slot           text not null check (x_slot in ('a', 'b')),
  state            jsonb not null,              -- rules.gd serialize() snapshot
  rev              text not null,               -- optimistic-concurrency version
  a_player_id      text references nw_players (id) on delete set null,
  a_name           text not null,
  a_hero           text not null,
  a_token_hash     text not null,               -- sha256 of the host seat token
  a_seen_at        timestamptz not null,
  a_rematch        boolean not null default false,
  b_player_id      text references nw_players (id) on delete set null,
  b_name           text,
  b_hero           text,
  b_token_hash     text,
  b_seen_at        timestamptz,
  b_rematch        boolean not null default false,
  left_slot        text check (left_slot in ('a', 'b')),
  winner_slot      text check (winner_slot in ('a', 'b')),
  end_reason       text,                        -- win | draw | forfeit | timeout | cancelled | expired
  turn_started_at  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- A code is unique among live rooms; closed rooms may share a recycled code.
create unique index if not exists nw_rooms_live_code on nw_rooms (code) where status <> 'closed';
create index if not exists nw_rooms_code on nw_rooms (code, created_at desc);
create index if not exists nw_rooms_lobby
  on nw_rooms (created_at desc) where status = 'waiting' and not is_private;
create index if not exists nw_rooms_status_activity on nw_rooms (status, updated_at);
create index if not exists nw_rooms_active_turn on nw_rooms (turn_started_at) where status = 'active';

-- Append-only log of completed matches (one per room round).
create table if not exists nw_matches (
  id           bigserial primary key,
  room_id      text not null references nw_rooms (id) on delete cascade,
  round        integer not null,
  x_player_id  text references nw_players (id) on delete set null,
  o_player_id  text references nw_players (id) on delete set null,
  x_name       text not null,
  o_name       text not null,
  x_hero       text not null,
  o_hero       text not null,
  result       text not null check (result in ('x', 'o', 'draw')),
  end_reason   text not null check (end_reason in ('win', 'draw', 'forfeit', 'timeout')),
  x_boards     integer not null,
  o_boards     integer not null,
  moves        integer not null,
  ended_at     timestamptz not null default now(),
  unique (room_id, round)
);
create index if not exists nw_matches_x_player on nw_matches (x_player_id, ended_at desc);
create index if not exists nw_matches_o_player on nw_matches (o_player_id, ended_at desc);
