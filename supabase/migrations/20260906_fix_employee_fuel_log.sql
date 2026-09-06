-- Makes employee BBM submissions compatible with the fuel form.
-- Safe to run on databases that already have these columns.
alter table public.fuel_logs add column if not exists fuel_type text;
alter table public.fuel_logs add column if not exists vendor_name text;

-- Employees can submit fuel records only on behalf of their own account.
grant select, insert on public.fuel_logs to authenticated;
drop policy if exists "fuel employee submit" on public.fuel_logs;
create policy "fuel employee submit" on public.fuel_logs
  for insert to authenticated
  with check (employee_id = auth.uid());

-- Refresh PostgREST's schema cache so the new fields are immediately accepted.
notify pgrst, 'reload schema';
