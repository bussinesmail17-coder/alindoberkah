-- Include every non-Super-Admin company user in the cash employee picker.
-- Some existing employee accounts have already been reassigned to HR/Finance,
-- so filtering exclusively by the legacy `employee` role leaves the picker empty.

create or replace function public.cash_transaction_employee_options()
returns table (id uuid, employee_code text, full_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('admin', 'hr', 'finance')
  ) then
    raise exception 'Akses Finance, HR, atau Super Admin diperlukan.' using errcode = '42501';
  end if;

  return query
    select p.id, p.employee_code, p.full_name
    from public.profiles p
    where p.role in ('employee', 'hr', 'finance')
    order by coalesce(p.employee_code, ''), p.full_name;
end;
$$;

grant execute on function public.cash_transaction_employee_options() to authenticated;
