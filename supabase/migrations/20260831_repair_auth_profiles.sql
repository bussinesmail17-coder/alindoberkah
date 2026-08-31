-- Repair akun Auth yang belum memiliki profile dan pastikan akun baru tersinkron otomatis.

alter table public.profiles
  add column if not exists employee_code text;

create unique index if not exists profiles_employee_code_unique
  on public.profiles (employee_code)
  where employee_code is not null;

create sequence if not exists public.employee_code_seq start with 1 increment by 1;

select setval(
  'public.employee_code_seq',
  greatest(
    coalesce((
      select max(nullif(regexp_replace(employee_code, '[^0-9]', '', 'g'), '')::bigint)
      from public.profiles
    ), 0),
    1
  ),
  coalesce((select max(nullif(regexp_replace(employee_code, '[^0-9]', '', 'g'), '')::bigint) from public.profiles), 0) > 0
);

create or replace function public.assign_employee_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'employee' and new.employee_code is null then
    new.employee_code := 'HMA' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_assign_employee_code on public.profiles;
create trigger profiles_assign_employee_code
before insert on public.profiles
for each row execute function public.assign_employee_code();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(new.email, 'Karyawan'), '@', 1)),
    new.email,
    case when lower(coalesce(new.email, '')) = 'bussinesmail17@gmail.com' then 'admin' else 'employee' end
  )
  on conflict (id) do update
  set email = excluded.email,
      full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
      role = case
        when lower(coalesce(excluded.email, '')) = 'bussinesmail17@gmail.com' then 'admin'
        else public.profiles.role
      end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Backfill semua akun yang sudah terlanjur dibuat di Authentication.
insert into public.profiles (id, full_name, email, role)
select
  users.id,
  coalesce(nullif(users.raw_user_meta_data ->> 'full_name', ''), split_part(coalesce(users.email, 'Karyawan'), '@', 1)),
  users.email,
  case when lower(coalesce(users.email, '')) = 'bussinesmail17@gmail.com' then 'admin' else 'employee' end
from auth.users as users
on conflict (id) do update
set email = excluded.email,
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
    role = case
      when lower(coalesce(excluded.email, '')) = 'bussinesmail17@gmail.com' then 'admin'
      else public.profiles.role
    end;

update public.profiles
set employee_code = 'HMA' || lpad(nextval('public.employee_code_seq')::text, 3, '0')
where role = 'employee' and employee_code is null;

update public.profiles
set employee_code = null
where role <> 'employee';

select id, employee_code, full_name, email, role
from public.profiles
order by created_at asc nulls last, email;
