-- Nineweave online tournaments (round 5, phase 3): single-elimination
-- brackets of 3–8 device players with a screen name. Each bracket match is a
-- normal nw_rooms room linked back to its tournament.
--
-- PII: only public screen names (copied into nw_tournament_players) and the
-- player ids that link them. Tournament passwords are scrypt hashes. Finished
-- and cancelled tournaments (and their player / match rows) are deleted
-- 7 days after their last update by the opportunistic sweep (no cron).

-- Tournaments won (champion of a finished online tournament).
alter table nw_players add column if not exists tournament_wins integer not null default 0;

create table if not exists nw_tournaments (
  id                  text primary key,
  code                text not null,               -- "T" + five uppercase letters/digits
  status              text not null check (status in ('registering', 'starting', 'running', 'finished', 'cancelled')),
  size                integer not null check (size in (4, 8)),  -- seats offered
  bracket_size        integer,                     -- power of two set at start (4 or 8)
  is_private          boolean not null default false,
  password_hash       text,                        -- scrypt; null for public tournaments
  host_player_id      text references nw_players (id) on delete set null,
  starts_at           timestamptz not null,
  starting_at         timestamptz,                 -- 10 s countdown once the bracket is full
  started_at          timestamptz,
  finished_at         timestamptz,
  cancel_reason       text,
  champion_player_id  text references nw_players (id) on delete set null,
  champion_name       text,
  champion_hero       text,
  rev                 text not null,               -- optimistic-concurrency version
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
-- A code is unique among live tournaments; ended ones may share a recycled code.
create unique index if not exists nw_tournaments_live_code
  on nw_tournaments (code) where status in ('registering', 'starting', 'running');
create index if not exists nw_tournaments_code on nw_tournaments (code, created_at desc);
create index if not exists nw_tournaments_lobby
  on nw_tournaments (created_at desc) where status in ('registering', 'starting') and not is_private;
create index if not exists nw_tournaments_due
  on nw_tournaments (starts_at) where status in ('registering', 'starting');
create index if not exists nw_tournaments_updated on nw_tournaments (updated_at);

create table if not exists nw_tournament_players (
  tournament_id  text not null references nw_tournaments (id) on delete cascade,
  player_id      text not null references nw_players (id) on delete cascade,
  name           text not null,                   -- screen name when joined (public)
  hero           text not null,
  seed           integer,                         -- 1 = top seed; set (randomly) at start
  eliminated     boolean not null default false,
  withdrawn      boolean not null default false,  -- left after the start
  joined_at      timestamptz not null default now(),
  primary key (tournament_id, player_id)
);
create index if not exists nw_tournament_players_player on nw_tournament_players (player_id);

-- One row per bracket slot. Round 1 is the first round; slot k of round r is
-- fed by slots 2k (side a) and 2k+1 (side b) of round r - 1.
create table if not exists nw_tournament_matches (
  tournament_id  text not null references nw_tournaments (id) on delete cascade,
  round          integer not null,
  slot           integer not null,
  a_player_id    text references nw_players (id) on delete set null,
  b_player_id    text references nw_players (id) on delete set null,
  a_seed         integer,
  b_seed         integer,
  bye            boolean not null default false,
  status         text not null check (status in ('pending', 'ready', 'live', 'done')),
  room_id        text references nw_rooms (id) on delete set null,
  winner         text check (winner in ('a', 'b')),
  end_reason     text,
  a_boards       integer,
  b_boards       integer,
  updated_at     timestamptz not null default now(),
  primary key (tournament_id, round, slot)
);

-- Tournament rooms: the bracket link and the 60 s ready window.
alter table nw_rooms add column if not exists tournament_id text references nw_tournaments (id) on delete set null;
alter table nw_rooms add column if not exists tournament_code text;
alter table nw_rooms add column if not exists tournament_round integer;
alter table nw_rooms add column if not exists tournament_slot integer;
alter table nw_rooms add column if not exists ready_deadline timestamptz;
alter table nw_rooms add column if not exists a_ready_at timestamptz;
alter table nw_rooms add column if not exists b_ready_at timestamptz;
create index if not exists nw_rooms_ready_deadline
  on nw_rooms (ready_deadline) where status = 'waiting' and tournament_id is not null;

-- A tournament draw with more small boards on one side is a recorded win
-- ("boards").
alter table nw_matches drop constraint if exists nw_matches_end_reason_check;
alter table nw_matches add constraint nw_matches_end_reason_check
  check (end_reason in ('win', 'draw', 'forfeit', 'timeout', 'abandoned', 'boards'));
