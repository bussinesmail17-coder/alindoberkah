-- Payroll is authored by Admin/HR. The database calculates work days from
-- attendance so the browser cannot submit a forged attendance total.
create or replace function public.create_payroll_record(
  p_employee_id uuid,
  p_period_start date,
  p_base_salary numeric,
  p_allowance numeric default 0,
  p_deduction numeric default 0,
  p_payment_status text default 'pending'
)
returns table (
  id uuid,
  work_days integer,
  period_start date,
  period_end date,
  net_salary numeric,
  payment_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period_end date;
  v_work_days integer;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr')
  ) then
    raise exception 'Payroll hanya dapat dibuat oleh Admin atau HR.' using errcode = '42501';
  end if;

  if p_period_start is null or p_base_salary < 0 or p_allowance < 0 or p_deduction < 0 then
    raise exception 'Data payroll tidak valid.' using errcode = '22023';
  end if;

  if p_payment_status not in ('pending', 'approved', 'paid') then
    raise exception 'Status payroll tidak valid.' using errcode = '22023';
  end if;

  p_period_start := date_trunc('month', p_period_start)::date;
  v_period_end := (p_period_start + interval '1 month - 1 day')::date;

  select count(*)::integer
  into v_work_days
  from public.attendance
  where employee_id = p_employee_id
    and check_in_date between p_period_start and v_period_end
    and verification_status <> 'rejected';

  return query
  insert into public.payroll_records (
    employee_id, period_start, period_end, work_days,
    base_salary, allowance, deduction, payment_status
  )
  values (
    p_employee_id, p_period_start, v_period_end, v_work_days,
    p_base_salary, p_allowance, p_deduction, p_payment_status
  )
  on conflict (employee_id, period_start, period_end) do update
  set work_days = excluded.work_days,
      base_salary = excluded.base_salary,
      allowance = excluded.allowance,
      deduction = excluded.deduction,
      payment_status = excluded.payment_status
  returning payroll_records.id, payroll_records.work_days,
            payroll_records.period_start, payroll_records.period_end,
            payroll_records.net_salary, payroll_records.payment_status;
end;
$$;

grant execute on function public.create_payroll_record(uuid, date, numeric, numeric, numeric, text) to authenticated;
