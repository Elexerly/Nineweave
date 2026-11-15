-- Nineweave online2 (round 5): turn clock with a one-time "Still there?"
-- restart, no-show / abandoned match endings, in-match chat, player blocks
-- and reports.
--
-- PII: chat messages (free text a player typed, already filtered), the
-- sender's screen name, and report notes are personal data. Chat rows are
-- deleted 24 h after creation and 1 h after their room closes; reports (with
-- their chat snapshot) are deleted after 30 days. Blocks store only two
-- player ids. Message text is never logged.

-- When the guest took the second seat (null while waiting / legacy rows).
alter table nw_rooms add column if not exists b_joined_at timestamptz;
-- The player due to move used their one "Still there?" restart this turn.
alter table nw_rooms add column if not exists still_here_used boolean not null default false;

-- New match endings: "abandoned" (disconnect grace ran out after both players
-- moved) is a recorded result. ("no_show" cancels the room and is never
-- logged as a match.)
alter table nw_matches drop constraint if exists nw_matches_end_reason_check;
alter table nw_matches add constraint nw_matches_end_reason_check
  check (end_reason in ('win', 'draw', 'forfeit', 'timeout', 'abandoned'));

-- Sweep: active rooms whose idle seat may have run out of disconnect grace.
create index if not exists nw_rooms_active_seen
  on nw_rooms (least(a_seen_at, b_seen_at)) where status = 'active';

-- In-match chat. Only device players with a screen name can send.
create table if not exists nw_chat (
  id          bigserial primary key,
  room_id     text not null references nw_rooms (id) on delete cascade,
  round       integer not null,
  seat        integer not null check (seat in (1, 2)),   -- sender's seat in that round
  slot        text not null check (slot in ('a', 'b')),  -- sender's stable room slot
  player_id   text references nw_players (id) on delete cascade,
  name        text not null,                             -- sender's screen name when sent (PII: public name)
  text        text not null,                             -- filtered message text (PII)
  preset      text,                                      -- quick-chat key, or null for free text
  filtered    boolean not null default false,            -- profanity was masked
  created_at  timestamptz not null default now()
);
create index if not exists nw_chat_room on nw_chat (room_id, id);
create index if not exists nw_chat_player on nw_chat (player_id, created_at);
create index if not exists nw_chat_created on nw_chat (created_at);

-- Player blocks: the blocked player's chat is never delivered to the blocker
-- and they can't join the blocker's rooms.
create table if not exists nw_blocks (
  blocker_id  text not null references nw_players (id) on delete cascade,
  blocked_id  text not null references nw_players (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create index if not exists nw_blocks_blocked on nw_blocks (blocked_id);

-- Player reports for safety review, kept 30 days.
create table if not exists nw_reports (
  id             bigserial primary key,
  reporter_id    text references nw_players (id) on delete set null,
  reported_id    text references nw_players (id) on delete set null,  -- null: anonymous seat
  reported_name  text not null,                 -- name shown in the room (public)
  room_code      text not null,
  reason         text not null check (reason in ('harassment', 'hate', 'inappropriate_name', 'cheating', 'spam', 'other')),
  note           text,                          -- optional reporter note, <= 500 chars (PII)
  chat_snapshot  jsonb not null default '[]'::jsonb, -- reported player's last <= 20 messages in the room (PII)
  created_at     timestamptz not null default now()
);
create index if not exists nw_reports_reporter on nw_reports (reporter_id, created_at);
create index if not exists nw_reports_created on nw_reports (created_at);
