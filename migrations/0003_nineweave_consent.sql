-- Consent recorded when a player creates a screen name: which Terms and
-- Privacy versions they agreed to, when, and that they confirmed they are
-- 13 or older or have a parent or guardian's permission. All nullable so
-- existing anonymous device accounts stay valid.
alter table nw_players add column if not exists tos_version text;
alter table nw_players add column if not exists privacy_version text;
alter table nw_players add column if not exists accepted_at timestamptz;
alter table nw_players add column if not exists age_confirmed boolean;
