-- Per-seat protocol opt-in and board readiness belong to one match round.
-- Defaults preserve all rooms opened by existing clients.
alter table nw_rooms
  add column if not exists a_board_ready_v1 boolean not null default false,
  add column if not exists b_board_ready_v1 boolean not null default false,
  add column if not exists a_board_ready_at timestamptz,
  add column if not exists b_board_ready_at timestamptz,
  add column if not exists board_ready_deadline timestamptz;

create index if not exists nw_rooms_board_ready_deadline_idx
  on nw_rooms (board_ready_deadline)
  where status = 'active' and turn_started_at is null and board_ready_deadline is not null;
