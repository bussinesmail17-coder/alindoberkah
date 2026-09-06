-- Operational reliability: admin inputs are persisted, odometers stay current,
-- and only Admin/HR may create a report on behalf of a staff member.
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
language plpgsql
security definer
set search_path = public
as $$
declare result public.employee_reports%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Laporan hanya dapat dibuat oleh Admin, HR, atau Finance.' using errcode = '42501';
  end if;
  if p_employee_id is null or p_report_date is null or coalesce(trim(p_title),'') = '' or coalesce(trim(p_description),'') = ''
    or coalesce(p_success_count,0) < 0 or coalesce(p_failed_count,0) < 0
    or coalesce(p_cod_amount,0) < 0 or coalesce(p_dfod_amount,0) < 0 then
    raise exception 'Data laporan tidak lengkap atau tidak valid.' using errcode = '22023';
  end if;
  insert into public.employee_reports (
    employee_id, report_date, title, description, success_count, failed_count, cod_amount, dfod_amount
  ) values (
    p_employee_id, p_report_date, trim(p_title), trim(p_description), p_success_count, p_failed_count, p_cod_amount, p_dfod_amount
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.sync_vehicle_odometer_from_fuel_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.vehicles
  set current_odometer = greatest(current_odometer, new.current_odometer)
  where id = new.vehicle_id;
  return new;
end;
$$;

drop trigger if exists fuel_log_sync_vehicle_odometer on public.fuel_logs;
create trigger fuel_log_sync_vehicle_odometer
after insert on public.fuel_logs
for each row execute function public.sync_vehicle_odometer_from_fuel_log();

grant execute on function public.create_admin_employee_report(uuid,date,text,text,integer,integer,numeric,numeric) to authenticated;
