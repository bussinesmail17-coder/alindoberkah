-- HMA Operations: database schema for Supabase PostgreSQL.
-- Apply this migration only to a new, empty project.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text unique,
  role text not null default 'employee' check (role in ('admin','hr','finance','employee')),
  position text,
  phone text,
  base_salary numeric(14,2) not null default 0 check (base_salary >= 0),
  created_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(), plate_no text not null unique, model text,
  status text not null default 'active' check (status in ('active','maintenance','inactive')),
  current_odometer numeric(12,1) not null default 0, created_at timestamptz not null default now()
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  check_in_at timestamptz not null default now(), client_time timestamptz,
  check_out_at timestamptz, check_out_client_time timestamptz,
  check_in_date date not null default ((now() at time zone 'Asia/Jakarta')::date),
  latitude numeric(10,7) not null, longitude numeric(10,7) not null,
  accuracy_meters numeric(10,2), selfie_path text not null,
  check_out_latitude numeric(10,7), check_out_longitude numeric(10,7), check_out_accuracy_meters numeric(10,2), check_out_selfie_path text,
  shift_name text not null default 'Shift Pagi', shift_start_time time not null default time '08:00', shift_end_time time not null default time '16:00',
  late_minutes integer not null default 0 check (late_minutes >= 0), early_leave_minutes integer not null default 0 check (early_leave_minutes >= 0),
  verification_status text not null default 'submitted' check (verification_status in ('submitted','verified','rejected')),
  note text, created_at timestamptz not null default now(), unique (employee_id, check_in_date)
);

create table public.employee_reports (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.profiles(id) on delete cascade,
  report_date date not null default ((now() at time zone 'Asia/Jakarta')::date), title text not null, description text not null,
  success_count integer not null default 0 check (success_count >= 0), failed_count integer not null default 0 check (failed_count >= 0),
  cod_amount numeric(14,2) not null default 0 check (cod_amount >= 0), dfod_amount numeric(14,2) not null default 0 check (dfod_amount >= 0),
  evidence_path text, status text not null default 'submitted' check (status in ('submitted','reviewed','rejected')), created_at timestamptz not null default now()
);

create table public.employee_leave_requests (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('izin','cuti','sakit')), start_date date not null, end_date date not null,
  note text not null, status text not null default 'submitted' check (status in ('submitted','approved','rejected')),
  reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, review_note text, created_at timestamptz not null default now(), check (end_date >= start_date)
);
create table public.employee_cash_advances (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0), note text not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','paid')),
  reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, review_note text, created_at timestamptz not null default now()
);

create table public.fuel_logs (
  id uuid primary key default gen_random_uuid(), vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  employee_id uuid references public.profiles(id) on delete set null, filled_at timestamptz not null default now(),
  previous_odometer numeric(12,1) not null check (previous_odometer >= 0),
  current_odometer numeric(12,1) not null check (current_odometer >= previous_odometer),
  liters numeric(10,2) not null check (liters > 0), price_per_liter numeric(12,2) not null check (price_per_liter >= 0),
  total_amount numeric(14,2) generated always as (liters * price_per_liter) stored,
  distance_km numeric(12,1) generated always as (current_odometer - previous_odometer) stored,
  expected_liters numeric(12,2) generated always as ((current_odometer - previous_odometer) / 9.0) stored,
  created_at timestamptz not null default now()
);

create table public.cash_transactions (
  id uuid primary key default gen_random_uuid(), transaction_date date not null default ((now() at time zone 'Asia/Jakarta')::date),
  type text not null check (type in ('income','expense')), category text not null, description text,
  amount numeric(14,2) not null check (amount > 0), employee_id uuid references public.profiles(id) on delete set null,
  created_by uuid not null default auth.uid() references public.profiles(id), created_at timestamptz not null default now()
);

create table public.payroll_records (
  id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.profiles(id) on delete cascade,
  period_start date not null, period_end date not null, work_days integer not null default 0 check (work_days >= 0),
  base_salary numeric(14,2) not null default 0 check (base_salary >= 0), allowance numeric(14,2) not null default 0 check (allowance >= 0),
  deduction numeric(14,2) not null default 0 check (deduction >= 0),
  net_salary numeric(14,2) generated always as (base_salary + allowance - deduction) stored,
  payment_status text not null default 'pending' check (payment_status in ('pending','approved','paid')),
  created_at timestamptz not null default now(), unique (employee_id, period_start, period_end), check (period_end >= period_start)
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','hr','finance'));
$$;

create or replace function public.enforce_attendance_server_time() returns trigger language plpgsql security definer set search_path = public as $$
begin new.employee_id := auth.uid(); new.check_in_at := now(); new.check_in_date := (now() at time zone 'Asia/Jakarta')::date; return new; end;
$$;
create trigger attendance_server_time before insert on public.attendance for each row execute function public.enforce_attendance_server_time();

-- Every user created in Supabase Auth receives an employee profile automatically.
-- Promote the first owner by changing this profile's role to `admin` in SQL Editor.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, 'Karyawan'), '@', 1)), new.email, 'employee')
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Employee IDs are assigned server-side, sequentially: HMA001, HMA002, and so on.
alter table public.profiles add column employee_code text unique check (employee_code ~ '^HMA[0-9]{3,}$');
create sequence public.employee_code_seq start with 1 increment by 1;
create or replace function public.assign_employee_code() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'employee' and new.employee_code is null then
    new.employee_code := 'HMA' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;
create trigger profiles_assign_employee_code before insert on public.profiles for each row execute function public.assign_employee_code();

alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.attendance enable row level security;
alter table public.employee_reports enable row level security;
alter table public.fuel_logs enable row level security;
alter table public.cash_transactions enable row level security;
alter table public.payroll_records enable row level security;

create policy "profiles read own or admin" on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy "profiles admin manage" on public.profiles for all using (public.is_admin()) with check (public.is_admin());
create policy "vehicles read authenticated" on public.vehicles for select using (auth.uid() is not null);
create policy "vehicles admin manage" on public.vehicles for all using (public.is_admin()) with check (public.is_admin());
create policy "attendance read own or admin" on public.attendance for select using (employee_id = auth.uid() or public.is_admin());
create policy "attendance employee insert" on public.attendance for insert with check (auth.uid() is not null);
create policy "attendance admin manage" on public.attendance for update using (public.is_admin()) with check (public.is_admin());
create policy "reports read own or admin" on public.employee_reports for select using (employee_id = auth.uid() or public.is_admin());
create policy "reports employee insert" on public.employee_reports for insert with check (employee_id = auth.uid());
create policy "reports admin update" on public.employee_reports for update using (public.is_admin()) with check (public.is_admin());
create policy "fuel read authenticated" on public.fuel_logs for select using (auth.uid() is not null);
create policy "fuel admin manage" on public.fuel_logs for all using (public.is_admin()) with check (public.is_admin());
create policy "fuel employee submit" on public.fuel_logs for insert with check (auth.uid() is not null and employee_id = auth.uid());
create policy "cash finance manage" on public.cash_transactions for all using (public.is_admin()) with check (public.is_admin());
create policy "payroll own or admin" on public.payroll_records for select using (employee_id = auth.uid() or public.is_admin());
create policy "payroll admin manage" on public.payroll_records for all using (public.is_admin()) with check (public.is_admin());

-- PostgREST table privileges; RLS above remains the authorization boundary.
grant select, insert, update, delete on table public.vehicles to authenticated;
grant select, insert, update on table public.employee_reports to authenticated;
grant select, insert, update, delete on table public.cash_transactions to authenticated;
grant select, insert, update, delete on table public.payroll_records to authenticated;
grant select, insert, update, delete on table public.vehicles to service_role;
grant select, insert, update, delete on table public.employee_reports to service_role;
grant select, insert, update, delete on table public.cash_transactions to service_role;
grant select, insert, update, delete on table public.payroll_records to service_role;

insert into storage.buckets (id, name, public) values ('attendance-selfies', 'attendance-selfies', false) on conflict (id) do nothing;
create policy "selfie employee upload" on storage.objects for insert to authenticated with check (bucket_id = 'attendance-selfies' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "selfie employee read" on storage.objects for select to authenticated using (bucket_id = 'attendance-selfies' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy "selfie employee delete" on storage.objects for delete to authenticated using (bucket_id = 'attendance-selfies' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-evidence', 'report-evidence', false, 5242880, array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;
create policy "employees upload own report evidence" on storage.objects for insert to authenticated with check (bucket_id = 'report-evidence' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "employees and admins read report evidence" on storage.objects for select to authenticated using (bucket_id = 'report-evidence' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy "employees remove own report evidence" on storage.objects for delete to authenticated using (bucket_id = 'report-evidence' and (storage.foldername(name))[1] = auth.uid()::text);
