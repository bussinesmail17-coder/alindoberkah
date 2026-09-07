-- A single, audited write path for cash entries from the Operations panel.
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
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr', 'finance')
  ) then
    raise exception 'Hanya Admin, HR, atau Finance yang dapat mencatat arus kas.' using errcode = '42501';
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
