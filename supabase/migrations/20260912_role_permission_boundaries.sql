-- Final role boundaries for HMA Operations.
-- UI visibility is helpful, but RLS remains the security boundary.

create or replace function public.is_hr_or_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr')
  );
$$;

create or replace function public.is_finance_or_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'finance')
  );
$$;

-- Profiles: HR may read employee data, while only Super Admin can alter it.
drop policy if exists "profiles read own or admin" on public.profiles;
drop policy if exists "profiles admin manage" on public.profiles;
create policy "profiles read own or hr" on public.profiles
  for select using (id = auth.uid() or public.is_hr_or_super_admin());
create policy "profiles super admin manage" on public.profiles
  for all using (public.is_super_admin()) with check (public.is_super_admin());

-- Attendance: HR can review/export; corrections remain Super Admin-only.
drop policy if exists "attendance read own or admin" on public.attendance;
drop policy if exists "attendance admin manage" on public.attendance;
drop policy if exists "attendance admin direct insert" on public.attendance;
create policy "attendance read own or hr" on public.attendance
  for select using (employee_id = auth.uid() or public.is_hr_or_super_admin());
create policy "attendance super admin update" on public.attendance
  for update using (public.is_super_admin()) with check (public.is_super_admin());
create policy "attendance super admin direct insert" on public.attendance
  for insert with check (public.is_super_admin());

-- Employee reports and requests are HR data, not Finance data.
drop policy if exists "reports read own or admin" on public.employee_reports;
drop policy if exists "reports admin update" on public.employee_reports;
create policy "reports read own or hr" on public.employee_reports
  for select using (employee_id = auth.uid() or public.is_hr_or_super_admin());
create policy "reports super admin update" on public.employee_reports
  for update using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "leave requests read own or admin" on public.employee_leave_requests;
drop policy if exists "leave requests admin manage" on public.employee_leave_requests;
create policy "leave requests read own or hr" on public.employee_leave_requests
  for select using (employee_id = auth.uid() or public.is_hr_or_super_admin());
create policy "leave requests hr manage" on public.employee_leave_requests
  for all using (public.is_hr_or_super_admin()) with check (public.is_hr_or_super_admin());

drop policy if exists "cash advances read own or admin" on public.employee_cash_advances;
drop policy if exists "cash advances admin manage" on public.employee_cash_advances;
create policy "cash advances read own or hr" on public.employee_cash_advances
  for select using (employee_id = auth.uid() or public.is_hr_or_super_admin());
create policy "cash advances hr manage" on public.employee_cash_advances
  for all using (public.is_hr_or_super_admin()) with check (public.is_hr_or_super_admin());

-- Finance owns cash flow. Payroll is shared only by HR, Finance, and Super Admin.
drop policy if exists "cash finance manage" on public.cash_transactions;
create policy "cash finance manage" on public.cash_transactions
  for all using (public.is_finance_or_super_admin()) with check (public.is_finance_or_super_admin());

drop policy if exists "payroll own or admin" on public.payroll_records;
drop policy if exists "payroll admin manage" on public.payroll_records;
create policy "payroll own or finance hr" on public.payroll_records
  for select using (employee_id = auth.uid() or public.is_hr_or_super_admin() or public.is_finance_or_super_admin());
create policy "payroll finance hr manage" on public.payroll_records
  for all using (public.is_hr_or_super_admin() or public.is_finance_or_super_admin())
  with check (public.is_hr_or_super_admin() or public.is_finance_or_super_admin());

-- Operational master data and fuel validation remain Super Admin-only.
drop policy if exists "vehicles admin manage" on public.vehicles;
create policy "vehicles super admin manage" on public.vehicles
  for all using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "fuel read authenticated" on public.fuel_logs;
drop policy if exists "fuel admin manage" on public.fuel_logs;
create policy "fuel read own or super admin" on public.fuel_logs
  for select using (employee_id = auth.uid() or public.is_super_admin());
create policy "fuel super admin manage" on public.fuel_logs
  for all using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "attendance zones admin manage" on public.attendance_zones;
create policy "attendance zones super admin manage" on public.attendance_zones
  for all using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "fuel type admin manage" on public.fuel_types;
drop policy if exists "fuel vendor admin manage" on public.fuel_vendors;
drop policy if exists "fuel price admin manage" on public.fuel_prices;
create policy "fuel type super admin manage" on public.fuel_types
  for all using (public.is_super_admin()) with check (public.is_super_admin());
create policy "fuel vendor super admin manage" on public.fuel_vendors
  for all using (public.is_super_admin()) with check (public.is_super_admin());
create policy "fuel price super admin manage" on public.fuel_prices
  for all using (public.is_super_admin()) with check (public.is_super_admin());

-- The attendance report RPC must follow the same HR boundary.
-- Keep its existing response shape so the dashboard remains compatible.
drop function if exists public.admin_attendance_records();
create function public.admin_attendance_records()
returns table (
  id uuid, check_in_date date, check_in_at timestamptz, check_out_at timestamptz,
  verification_status text, note text, late_minutes integer,
  check_in_zone_distance_meters numeric, full_name text, employee_position text
)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_hr_or_super_admin() then
    raise exception 'Akses absensi HR diperlukan.' using errcode = '42501';
  end if;
  return query
    select a.id, a.check_in_date, a.check_in_at, a.check_out_at,
      a.verification_status, a.note, a.late_minutes,
      a.check_in_zone_distance_meters, p.full_name, p.position
    from public.attendance a
    join public.profiles p on p.id = a.employee_id
    order by a.check_in_date desc, a.check_in_at desc;
end;
$$;

grant execute on function public.is_hr_or_super_admin() to authenticated;
grant execute on function public.is_finance_or_super_admin() to authenticated;
grant execute on function public.admin_attendance_records() to authenticated;

-- HR and Super Admin may create a report on behalf of an employee.
create or replace function public.create_admin_employee_report(
  p_employee_id uuid,
  p_report_date date,
  p_title text,
  p_description text,
  p_success_count integer default 0,
  p_failed_count integer default 0,
  p_cod_amount numeric default 0,
  p_dfod_amount numeric default 0
)
returns public.employee_reports
language plpgsql security definer set search_path = public as $$
declare result public.employee_reports%rowtype;
begin
  if not public.is_hr_or_super_admin() then
    raise exception 'Laporan hanya dapat dibuat oleh HR atau Super Admin.' using errcode = '42501';
  end if;
  if p_employee_id is null or p_report_date is null or coalesce(trim(p_title),'') = '' or coalesce(trim(p_description),'') = ''
    or coalesce(p_success_count,0) < 0 or coalesce(p_failed_count,0) < 0
    or coalesce(p_cod_amount,0) < 0 or coalesce(p_dfod_amount,0) < 0 then
    raise exception 'Data laporan tidak lengkap atau tidak valid.' using errcode = '22023';
  end if;
  insert into public.employee_reports (employee_id, report_date, title, description, success_count, failed_count, cod_amount, dfod_amount)
  values (p_employee_id, p_report_date, trim(p_title), trim(p_description), p_success_count, p_failed_count, p_cod_amount, p_dfod_amount)
  returning * into result;
  return result;
end;
$$;
grant execute on function public.create_admin_employee_report(uuid,date,text,text,integer,integer,numeric,numeric) to authenticated;

-- Keep the server-side cash-entry RPC aligned with the Finance workspace.
create or replace function public.record_cash_transaction(
  p_transaction_date date,
  p_type text,
  p_category text,
  p_description text,
  p_amount numeric,
  p_employee_id uuid default null
)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.cash_transactions%rowtype;
begin
  if not public.is_finance_or_super_admin() then
    raise exception 'Hanya Finance atau Super Admin yang dapat mencatat arus kas.' using errcode = '42501';
  end if;

  if p_transaction_date is null
    or p_type not in ('income', 'expense')
    or coalesce(trim(p_category), '') = ''
    or coalesce(trim(p_description), '') = ''
    or coalesce(p_amount, 0) <= 0 then
    raise exception 'Data transaksi kas belum lengkap atau nominal tidak valid.' using errcode = '22023';
  end if;

  insert into public.cash_transactions (
    transaction_date, type, category, description, amount, employee_id, created_by
  ) values (
    p_transaction_date, p_type, trim(p_category), trim(p_description), p_amount, p_employee_id, auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function public.record_cash_transaction(date,text,text,text,numeric,uuid) to authenticated;

-- Excel imports may reference the visible employee code (for example HMA001)
-- without exposing internal profile UUIDs to Finance users.
create or replace function public.record_cash_transaction_by_employee_code(
  p_transaction_date date,
  p_type text,
  p_category text,
  p_description text,
  p_amount numeric,
  p_employee_code text default null
)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  resolved_employee_id uuid;
begin
  if coalesce(trim(p_employee_code), '') <> '' then
    select id into resolved_employee_id
    from public.profiles
    where upper(employee_code) = upper(trim(p_employee_code));
    if resolved_employee_id is null then
      raise exception 'Kode karyawan % tidak ditemukan.', p_employee_code using errcode = '22023';
    end if;
  end if;

  return public.record_cash_transaction(
    p_transaction_date, p_type, p_category, p_description, p_amount, resolved_employee_id
  );
end;
$$;
grant execute on function public.record_cash_transaction_by_employee_code(date,text,text,text,numeric,text) to authenticated;
notify pgrst, 'reload schema';
