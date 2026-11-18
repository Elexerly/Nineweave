-- Completed late OWN turns, reset by a timely own move or a new match.
-- The current turn is derived from its existing authoritative timestamp.
alter table nw_rooms add column if not exists a_late_turns integer not null default 0 check (a_late_turns between 0 and 3);
alter table nw_rooms add column if not exists b_late_turns integer not null default 0 check (b_late_turns between 0 and 3);
