-- Bootstrap settings and shared admin attempt accounting. Always read these
-- from the host's DATABASE_URL, regardless of the active Nineweave database.
create table if not exists nw_admin_config (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);
