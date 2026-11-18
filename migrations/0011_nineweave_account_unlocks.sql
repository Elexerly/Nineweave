-- Independent of optional version-gate migration 0010. Account deletion cascades.
create table if not exists nw_account_unlocks (
  player_id text not null references nw_players(id) on delete cascade,
  kind text not null check (kind in ('background', 'hero')),
  unlock_id text not null,
  granted_at timestamptz not null default now(),
  primary key(player_id, kind, unlock_id)
);
-- One bounded row per account, shared by every API instance/device.
create table if not exists nw_unlock_rate (
  player_id text primary key references nw_players(id) on delete cascade,
  window_start timestamptz not null,
  attempts integer not null check (attempts > 0)
);
-- nw_players.unlocks is client-asserted legacy data, NOT proof of ownership.
-- Preserve it unchanged; never backfill permanent entitlements from it.
-- Existing players redeem a recognized code through the authenticated endpoint.
