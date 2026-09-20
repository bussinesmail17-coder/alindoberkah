-- Jalankan SATU KALI pada project Supabase perusahaan baru, sebelum membuat
-- akun karyawan pertama. Ganti semua teks ABC dengan prefix perusahaan.
-- Contoh: PT Contoh Jaya memakai prefix CTJ -> CTJ001, CTJ002, dst.

begin;

alter table public.profiles
  drop constraint if exists profiles_employee_code_check;

alter table public.profiles
  add constraint profiles_employee_code_check
  check (employee_code is null or employee_code ~ '^ABC[0-9]{3,}$');

create or replace function public.assign_employee_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'employee' and new.employee_code is null then
    new.employee_code := 'ABC' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;

commit;
