-- HR and Finance share the cash-entry workflow, including employee tagging.
-- Super Admin remains the only role with permanent-delete capabilities.

drop policy if exists "cash finance manage" on public.cash_transactions;
drop policy if exists "cash finance hr manage" on public.cash_transactions;
create policy "cash finance hr manage" on public.cash_transactions
  for all
  using (public.is_finance_or_super_admin() or public.is_hr_or_super_admin())
  with check (public.is_finance_or_super_admin() or public.is_hr_or_super_admin());

-- Dedicated minimal list for the employee selector. This avoids exposing
-- private profile columns through the general profiles policy.
create or replace function public.cash_transaction_employee_options_v2()
returns table (id uuid, employee_code text, full_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_finance_or_super_admin() or public.is_hr_or_super_admin()) then
    raise exception 'Akses Finance, HR, atau Super Admin diperlukan.' using errcode = '42501';
  end if;

  return query
    select p.id, p.employee_code, p.full_name
    from public.profiles p
    where coalesce(trim(p.full_name), '') <> ''
    order by coalesce(p.employee_code, ''), p.full_name;
end;
$$;

revoke all on function public.cash_transaction_employee_options_v2() from public;
grant execute on function public.cash_transaction_employee_options_v2() to authenticated;

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
  if not (public.is_finance_or_super_admin() or public.is_hr_or_super_admin()) then
    raise exception 'Hanya Finance, HR, atau Super Admin yang dapat mencatat arus kas.' using errcode = '42501';
  end if;

  if p_transaction_date is null
    or p_type not in ('income', 'expense')
    or coalesce(trim(p_category), '') = ''
    or coalesce(trim(p_description), '') = ''
    or coalesce(p_amount, 0) <= 0 then
    raise exception 'Data transaksi kas belum lengkap atau nominal tidak valid.' using errcode = '22023';
  end if;

  if p_employee_id is not null and not exists (
    select 1 from public.profiles where id = p_employee_id
  ) then
    raise exception 'Nama karyawan yang dipilih tidak ditemukan.' using errcode = '22023';
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
