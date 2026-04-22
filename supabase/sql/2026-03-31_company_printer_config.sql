-- Optional company-level printer configuration.
-- Example:
-- {
--   "type": "bluetooth",
--   "device_name": "XP-58",
--   "device_address": "66:32:AA:10:9B:21",
--   "ip": null,
--   "port": 9100
-- }

alter table if exists public.companies
  add column if not exists printer jsonb;
