-- Acuan konsumsi BBM: Solar 1 L / 7 KM; Pertalite dan jenis lain 1 L / 9 KM.
-- expected_liters adalah kolom turunan agar validasi dan laporan memakai aturan yang sama.
alter table public.fuel_logs drop column if exists expected_liters;

alter table public.fuel_logs add column expected_liters numeric(12,2)
generated always as (
  (current_odometer - previous_odometer) /
  case when lower(trim(coalesce(fuel_type, 'Pertalite'))) = 'solar' then 7.0 else 9.0 end
) stored;

comment on column public.fuel_logs.expected_liters is
  'Estimasi liter berdasarkan jenis BBM: Solar 7 KM/L, Pertalite dan lainnya 9 KM/L.';

notify pgrst, 'reload schema';
