-- Provide a minimal employee picker for Finance, HR, and Super Admin.
-- This intentionally exposes only the identifiers needed to tag a cash entry,
-- not private profile fields such as email, phone, or salary.

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
    where p.role = 'employee'
    order by coalesce(p.employee_code, ''), p.full_name;
end;
$$;

grant execute on function public.cash_transaction_employee_options() to authenticated;
