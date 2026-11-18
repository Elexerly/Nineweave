-- Account-scoped monotonic onboarding marker; deleted with the player row.
-- Existing clients with account-specific local completion may mark it via the API.
alter table nw_players add column if not exists tutorial_completed boolean not null default false;
-- Preserve the original turn start while bounding an acknowledged turn to 10s.
alter table nw_rooms add column if not exists still_here_confirmed_at timestamptz;
