-- Optional player email with server-owned ownership verification.
-- Email is PII: it is stored lowercased on the player and on each
-- verification challenge, never shown on the leaderboard, and only the
-- SHA-256 of a one-time code is kept (never the code itself).

alter table nw_players add column if not exists email text;               -- lowercased; null = none
alter table nw_players add column if not exists email_verified_at timestamptz; -- null = unverified

-- A verified email belongs to exactly one player. Unverified copies of the
-- same address may sit on several players until one of them confirms.
create unique index if not exists nw_players_verified_email
  on nw_players (lower(email)) where email_verified_at is not null;
create index if not exists nw_players_email_lower
  on nw_players (lower(email)) where email is not null;

-- One row per emailed code. Rows are kept for a day after creation so the
-- per-player and per-email hourly caps can be counted across instances.
create table if not exists nw_email_challenges (
  id              text primary key,                -- public challenge id ("ec_…")
  player_id       text not null references nw_players (id) on delete cascade,
  email           text not null,                   -- lowercased address the code was sent to
  purpose         text not null check (purpose in ('verify', 'recover')),
  code_hash       text not null,                   -- sha256 over challenge id + code
  expires_at      timestamptz not null,
  attempt_count   integer not null default 0,
  max_attempts    integer not null default 5,
  consumed_at     timestamptz,                     -- set on a successful confirm
  invalidated_at  timestamptz,                     -- superseded, send failed, or email claimed
  created_at      timestamptz not null default now()
);
create index if not exists nw_email_challenges_player
  on nw_email_challenges (player_id, created_at desc);
create index if not exists nw_email_challenges_email
  on nw_email_challenges (email, created_at desc);
create index if not exists nw_email_challenges_created
  on nw_email_challenges (created_at);
