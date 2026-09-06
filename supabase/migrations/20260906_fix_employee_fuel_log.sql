-- Makes employee BBM submissions compatible with the fuel form.
-- Safe to run on databases that already have these columns.
alter table public.fuel_logs add column if not exists fuel_type text;
alter table public.fuel_logs add column if not exists vendor_name text;

-- Refresh PostgREST's schema cache so the new fields are immediately accepted.
notify pgrst, 'reload schema';
