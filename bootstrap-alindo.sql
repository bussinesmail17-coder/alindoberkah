-- Alindo bootstrap: ONLY for empty project xydnmspjhsaciyhqestv.

begin;

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
  fuel_type text not null default 'Pertalite',
  total_amount numeric(14,2) generated always as (liters * price_per_liter) stored,
  distance_km numeric(12,1) generated always as (current_odometer - previous_odometer) stored,
  expected_liters numeric(12,2) generated always as ((current_odometer - previous_odometer) / case when lower(trim(coalesce(fuel_type, 'Pertalite'))) = 'solar' then 7.0 else 9.0 end) stored,
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


-- SOURCE: 20260831_attendance_checkout_shift.sql

alter table public.attendance
  add column if not exists check_out_at timestamptz,
  add column if not exists check_out_client_time timestamptz,
  add column if not exists check_out_latitude numeric(10,7),
  add column if not exists check_out_longitude numeric(10,7),
  add column if not exists check_out_accuracy_meters numeric(10,2),
  add column if not exists check_out_selfie_path text,
  add column if not exists shift_name text not null default 'Shift Pagi',
  add column if not exists shift_start_time time not null default time '08:00',
  add column if not exists shift_end_time time not null default time '16:00';

create or replace function public.check_out_attendance(
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_meters numeric,
  p_selfie_path text,
  p_client_time timestamptz default null
)
returns public.attendance
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.attendance%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sesi karyawan tidak ditemukan.';
  end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then
    raise exception 'Selfie dan lokasi check-out wajib dilengkapi.';
  end if;
  update public.attendance
     set check_out_at = now(),
         check_out_client_time = p_client_time,
         check_out_latitude = p_latitude,
         check_out_longitude = p_longitude,
         check_out_accuracy_meters = p_accuracy_meters,
         check_out_selfie_path = p_selfie_path
   where employee_id = auth.uid()
     and check_in_date = (now() at time zone 'Asia/Jakarta')::date
     and check_out_at is null
  returning * into result;
  if not found then
    raise exception 'Check-in hari ini tidak ditemukan atau check-out sudah dicatat.';
  end if;
  return result;
end;
$$;

grant execute on function public.check_out_attendance(numeric,numeric,numeric,text,timestamptz) to authenticated;


-- SOURCE: 20260831_cash_transaction_permissions.sql

-- Allow authenticated finance/admin users to use cash transactions.
-- Row-level policy public.is_admin() remains the authorization boundary.
grant select, insert, update, delete on table public.cash_transactions to authenticated;
grant select, insert, update, delete on table public.cash_transactions to service_role;


-- SOURCE: 20260831_create_payroll_rpc.sql

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


-- SOURCE: 20260831_employee_leave_and_cash_advance.sql

create table if not exists public.employee_leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('izin','cuti','sakit')),
  start_date date not null,
  end_date date not null,
  note text not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint leave_request_dates check (end_date >= start_date)
);

create table if not exists public.employee_cash_advances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0),
  note text not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','paid')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);

alter table public.employee_leave_requests enable row level security;
alter table public.employee_cash_advances enable row level security;

create policy "leave requests read own or admin" on public.employee_leave_requests for select using (employee_id = auth.uid() or public.is_admin());
create policy "leave requests employee submit" on public.employee_leave_requests for insert with check (employee_id = auth.uid());
create policy "leave requests admin manage" on public.employee_leave_requests for all using (public.is_admin()) with check (public.is_admin());
create policy "cash advances read own or admin" on public.employee_cash_advances for select using (employee_id = auth.uid() or public.is_admin());
create policy "cash advances employee submit" on public.employee_cash_advances for insert with check (employee_id = auth.uid());
create policy "cash advances admin manage" on public.employee_cash_advances for all using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on public.employee_leave_requests to authenticated;
grant select, insert, update on public.employee_cash_advances to authenticated;


-- SOURCE: 20260831_fuel_master.sql

-- Jalankan sekali di Supabase SQL Editor untuk mengaktifkan input BBM oleh karyawan.
create table if not exists public.fuel_types (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.fuel_vendors (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.fuel_prices (
  id uuid primary key default gen_random_uuid(), fuel_type_id uuid not null references public.fuel_types(id) on delete restrict,
  vendor_id uuid references public.fuel_vendors(id) on delete set null,
  price_per_liter numeric(12,2) not null check (price_per_liter > 0),
  effective_from date not null default current_date, is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.fuel_logs add column if not exists fuel_type text;
alter table public.fuel_logs add column if not exists vendor_name text;
alter table public.fuel_types enable row level security;
alter table public.fuel_vendors enable row level security;
alter table public.fuel_prices enable row level security;
grant select on public.fuel_types, public.fuel_vendors, public.fuel_prices to authenticated;
grant insert, update, delete on public.fuel_types, public.fuel_vendors, public.fuel_prices to authenticated;
create policy "fuel masters read authenticated" on public.fuel_types for select using (auth.uid() is not null);
create policy "fuel type admin manage" on public.fuel_types for all using (public.is_admin()) with check (public.is_admin());
create policy "fuel vendors read authenticated" on public.fuel_vendors for select using (auth.uid() is not null);
create policy "fuel vendor admin manage" on public.fuel_vendors for all using (public.is_admin()) with check (public.is_admin());
create policy "fuel prices read authenticated" on public.fuel_prices for select using (auth.uid() is not null);
create policy "fuel price admin manage" on public.fuel_prices for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "fuel employee submit" on public.fuel_logs;
create policy "fuel employee submit" on public.fuel_logs for insert with check (auth.uid() is not null and employee_id = auth.uid());
insert into public.fuel_types(name) values ('Pertalite'), ('Pertamax'), ('Solar') on conflict (name) do nothing;


-- SOURCE: 20260831_import_and_reports_permissions.sql

-- Minimal API grants. Row-level security policies still decide which rows/actions are allowed.
grant select on table public.vehicles to authenticated;
grant insert, update on table public.vehicles to authenticated;

grant select, insert on table public.employee_reports to authenticated;
grant update on table public.employee_reports to authenticated;

grant select, insert, update, delete on table public.vehicles to service_role;
grant select, insert, update, delete on table public.employee_reports to service_role;



-- SOURCE: 20260831_payroll_permissions.sql

-- Payroll is created and managed by Admin/HR according to the existing RLS policy.
grant select, insert, update, delete on table public.payroll_records to authenticated;
grant select, insert, update, delete on table public.payroll_records to service_role;


-- SOURCE: 20260831_profile_permissions.sql

-- Allow authenticated clients and trusted Edge Functions to reach profiles.
-- Row Level Security policies continue to decide which rows each session can use.
grant usage on schema public to authenticated, service_role;
revoke all privileges on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;
grant usage, select on sequence public.employee_code_seq to service_role;


-- SOURCE: 20260831_task_report_fields.sql

-- Structured task-result report fields and private photo evidence.
alter table public.employee_reports
  add column if not exists success_count integer not null default 0 check (success_count >= 0),
  add column if not exists failed_count integer not null default 0 check (failed_count >= 0),
  add column if not exists cod_amount numeric(14,2) not null default 0 check (cod_amount >= 0),
  add column if not exists dfod_amount numeric(14,2) not null default 0 check (dfod_amount >= 0),
  add column if not exists evidence_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-evidence',
  'report-evidence',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "employees upload own report evidence" on storage.objects;
create policy "employees upload own report evidence"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'report-evidence'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "employees and admins read report evidence" on storage.objects;
create policy "employees and admins read report evidence"
on storage.objects for select to authenticated
using (
  bucket_id = 'report-evidence'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

drop policy if exists "employees remove own report evidence" on storage.objects;
create policy "employees remove own report evidence"
on storage.objects for delete to authenticated
using (
  bucket_id = 'report-evidence'
  and (storage.foldername(name))[1] = auth.uid()::text
);


-- SOURCE: 20260901_attendance_zones.sql

-- Attendance zones are configured by Admin/HR. The initial zone covers Tangerang Selatan.
create table if not exists public.attendance_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  radius_meters numeric(10,2) not null check (radius_meters > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.attendance
  add column if not exists attendance_zone_id uuid references public.attendance_zones(id),
  add column if not exists check_in_zone_distance_meters numeric(10,2),
  add column if not exists check_out_zone_distance_meters numeric(10,2);

alter table public.attendance_zones enable row level security;
drop policy if exists "attendance zones read authenticated" on public.attendance_zones;
drop policy if exists "attendance zones admin manage" on public.attendance_zones;
create policy "attendance zones read authenticated" on public.attendance_zones for select using (auth.uid() is not null);
create policy "attendance zones admin manage" on public.attendance_zones for all using (public.is_admin()) with check (public.is_admin());
grant select, insert, update, delete on public.attendance_zones to authenticated;

-- Configure the Alindo attendance location before first attendance.

create or replace function public.active_attendance_zone()
returns public.attendance_zones
language plpgsql
security definer
set search_path = public
as $$
declare zone_row public.attendance_zones%rowtype;
begin
  select * into zone_row from public.attendance_zones where is_active order by created_at asc limit 1;
  if not found then raise exception 'Zona absensi belum diatur oleh administrator.'; end if;
  return zone_row;
end;
$$;

create or replace function public.distance_to_attendance_zone_meters(p_latitude numeric, p_longitude numeric, p_zone_latitude numeric, p_zone_longitude numeric)
returns numeric
language sql immutable
as $$
  select 6371000 * acos(least(1::numeric, greatest(-1::numeric,
    cos(radians(p_latitude)) * cos(radians(p_zone_latitude)) * cos(radians(p_zone_longitude) - radians(p_longitude))
    + sin(radians(p_latitude)) * sin(radians(p_zone_latitude))
  )));
$$;

create or replace function public.check_in_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare zone_row public.attendance_zones%rowtype; zone_distance numeric; result public.attendance%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  insert into public.attendance (employee_id,client_time,latitude,longitude,accuracy_meters,selfie_path,attendance_zone_id,check_in_zone_distance_meters)
  values (auth.uid(),p_client_time,p_latitude,p_longitude,p_accuracy_meters,p_selfie_path,zone_row.id,zone_distance)
  returning * into result;
  return result;
end;
$$;

create or replace function public.check_out_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare zone_row public.attendance_zones%rowtype; zone_distance numeric; result public.attendance%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag check-out wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  update public.attendance set check_out_at=now(), check_out_client_time=p_client_time, check_out_latitude=p_latitude,
    check_out_longitude=p_longitude, check_out_accuracy_meters=p_accuracy_meters, check_out_selfie_path=p_selfie_path,
    check_out_zone_distance_meters=zone_distance
  where employee_id=auth.uid() and check_in_date=(now() at time zone 'Asia/Jakarta')::date and check_out_at is null
  returning * into result;
  if not found then raise exception 'Check-in hari ini tidak ditemukan atau check-out sudah dicatat.'; end if;
  return result;
end;
$$;

drop policy if exists "attendance employee insert" on public.attendance;
create policy "attendance admin direct insert" on public.attendance for insert with check (public.is_admin());
grant execute on function public.check_in_attendance(numeric,numeric,numeric,text,timestamptz) to authenticated;
grant execute on function public.check_out_attendance(numeric,numeric,numeric,text,timestamptz) to authenticated;


-- SOURCE: 20260901_attendance_auto_photo_lateness.sql

alter table public.attendance
  add column if not exists late_minutes integer not null default 0 check (late_minutes >= 0),
  add column if not exists early_leave_minutes integer not null default 0 check (early_leave_minutes >= 0);

update public.attendance
set late_minutes = greatest(0, floor(extract(epoch from (((check_in_at at time zone 'Asia/Jakarta')::time) - shift_start_time)) / 60)::integer)
where check_in_at is not null;

create or replace function public.check_in_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare
  zone_row public.attendance_zones%rowtype;
  zone_distance numeric;
  result public.attendance%rowtype;
  server_local_time time := (now() at time zone 'Asia/Jakarta')::time;
  calculated_late integer;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  calculated_late := greatest(0, floor(extract(epoch from (server_local_time - time '08:00')) / 60)::integer);
  insert into public.attendance (
    employee_id, client_time, latitude, longitude, accuracy_meters, selfie_path,
    attendance_zone_id, check_in_zone_distance_meters, shift_name, shift_start_time, shift_end_time, late_minutes
  ) values (
    auth.uid(), p_client_time, p_latitude, p_longitude, p_accuracy_meters, p_selfie_path,
    zone_row.id, zone_distance, 'Shift Pagi', time '08:00', time '16:00', calculated_late
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.check_out_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare
  zone_row public.attendance_zones%rowtype;
  zone_distance numeric;
  result public.attendance%rowtype;
  server_local_time time := (now() at time zone 'Asia/Jakarta')::time;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag check-out wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  update public.attendance
  set check_out_at=now(), check_out_client_time=p_client_time, check_out_latitude=p_latitude,
      check_out_longitude=p_longitude, check_out_accuracy_meters=p_accuracy_meters, check_out_selfie_path=p_selfie_path,
      check_out_zone_distance_meters=zone_distance,
      early_leave_minutes=greatest(0, floor(extract(epoch from (shift_end_time - server_local_time)) / 60)::integer)
  where employee_id=auth.uid() and check_in_date=(now() at time zone 'Asia/Jakarta')::date and check_out_at is null
  returning * into result;
  if not found then raise exception 'Check-in hari ini tidak ditemukan atau check-out sudah dicatat.'; end if;
  return result;
end;
$$;

grant execute on function public.check_in_attendance(numeric,numeric,numeric,text,timestamptz) to authenticated;
grant execute on function public.check_out_attendance(numeric,numeric,numeric,text,timestamptz) to authenticated;


-- SOURCE: 20260901_attendance_read_models.sql

-- Stable read models for the employee and administration attendance screens.
-- The write RPCs already record attendance; these RPCs avoid a failed joined RLS
-- query leaving a valid record invisible in either dashboard.
create or replace function public.my_attendance_records()
returns table (
  check_in_date date,
  check_in_at timestamptz,
  check_out_at timestamptz,
  latitude numeric,
  longitude numeric,
  accuracy_meters numeric,
  selfie_path text,
  verification_status text,
  shift_name text,
  shift_start_time time,
  shift_end_time time,
  late_minutes integer,
  early_leave_minutes integer
)
language sql
security definer
set search_path = public
as $$
  select
    a.check_in_date, a.check_in_at, a.check_out_at,
    a.latitude, a.longitude, a.accuracy_meters, a.selfie_path,
    a.verification_status, a.shift_name, a.shift_start_time, a.shift_end_time,
    a.late_minutes, a.early_leave_minutes
  from public.attendance a
  where a.employee_id = auth.uid()
  order by a.check_in_date desc;
$$;

create or replace function public.admin_attendance_records()
returns table (
  check_in_date date,
  check_in_at timestamptz,
  check_out_at timestamptz,
  verification_status text,
  note text,
  late_minutes integer,
  check_in_zone_distance_meters numeric,
  full_name text,
  employee_position text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses absensi administrator diperlukan.';
  end if;

  return query
  select
    a.check_in_date, a.check_in_at, a.check_out_at,
    a.verification_status, a.note, a.late_minutes,
    a.check_in_zone_distance_meters, p.full_name, p.position
  from public.attendance a
  join public.profiles p on p.id = a.employee_id
  order by a.check_in_date desc, a.check_in_at desc;
end;
$$;

grant execute on function public.my_attendance_records() to authenticated;
grant execute on function public.admin_attendance_records() to authenticated;


-- SOURCE: 20260901_employee_profile_photo.sql

alter table public.profiles add column if not exists avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-avatars', 'employee-avatars', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=3145728, allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "employee avatar upload own" on storage.objects;
drop policy if exists "employee avatar update own" on storage.objects;
drop policy if exists "employee avatar read own or admin" on storage.objects;
drop policy if exists "employee avatar delete own or admin" on storage.objects;
create policy "employee avatar upload own" on storage.objects for insert to authenticated
  with check (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "employee avatar update own" on storage.objects for update to authenticated
  using (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text)
  with check (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "employee avatar read own or admin" on storage.objects for select to authenticated
  using (bucket_id='employee-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy "employee avatar delete own or admin" on storage.objects for delete to authenticated
  using (bucket_id='employee-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

drop function if exists public.update_my_profile(text,text);
create function public.update_my_profile(p_full_name text, p_phone text default null, p_avatar_path text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare result public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if char_length(trim(coalesce(p_full_name,''))) < 2 then raise exception 'Nama lengkap minimal 2 karakter.'; end if;
  if p_avatar_path is not null and split_part(p_avatar_path,'/',1) <> auth.uid()::text then
    raise exception 'Lokasi foto profil tidak valid.';
  end if;
  update public.profiles
     set full_name=trim(p_full_name), phone=nullif(trim(coalesce(p_phone,'')), ''), avatar_path=p_avatar_path
   where id=auth.uid()
   returning * into result;
  if not found then raise exception 'Profil karyawan tidak ditemukan.'; end if;
  return result;
end;
$$;

grant execute on function public.update_my_profile(text,text,text) to authenticated;


-- SOURCE: 20260901_employee_self_profile.sql

-- Employees may change only their own display name and phone number.
create or replace function public.update_my_profile(p_full_name text, p_phone text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare result public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sesi karyawan tidak ditemukan.';
  end if;
  if char_length(trim(coalesce(p_full_name,''))) < 2 then
    raise exception 'Nama lengkap minimal 2 karakter.';
  end if;
  update public.profiles
     set full_name = trim(p_full_name),
         phone = nullif(trim(coalesce(p_phone,'')), '')
   where id = auth.uid()
   returning * into result;
  if not found then
    raise exception 'Profil karyawan tidak ditemukan.';
  end if;
  return result;
end;
$$;

grant execute on function public.update_my_profile(text,text) to authenticated;


-- SOURCE: 20260906_disable_lateness_until_schedule.sql

-- Attendance is recorded without lateness/early-leave calculation until HR sets an official schedule.
update public.attendance
set late_minutes = 0, early_leave_minutes = 0
where late_minutes <> 0 or early_leave_minutes <> 0;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.check_in_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare
  zone_row public.attendance_zones%rowtype;
  zone_distance numeric;
  result public.attendance%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  insert into public.attendance (
    employee_id, client_time, latitude, longitude, accuracy_meters, selfie_path,
    attendance_zone_id, check_in_zone_distance_meters, shift_name, shift_start_time, shift_end_time, late_minutes, early_leave_minutes
  ) values (
    auth.uid(), p_client_time, p_latitude, p_longitude, p_accuracy_meters, p_selfie_path,
    zone_row.id, zone_distance, 'Jadwal belum ditetapkan', time '00:00', time '00:00', 0, 0
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.check_out_attendance(
  p_latitude numeric, p_longitude numeric, p_accuracy_meters numeric, p_selfie_path text, p_client_time timestamptz default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare
  zone_row public.attendance_zones%rowtype;
  zone_distance numeric;
  result public.attendance%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if p_latitude is null or p_longitude is null or coalesce(trim(p_selfie_path),'') = '' then raise exception 'Selfie dan geotag check-out wajib dilengkapi.'; end if;
  zone_row := public.active_attendance_zone();
  zone_distance := public.distance_to_attendance_zone_meters(p_latitude,p_longitude,zone_row.latitude,zone_row.longitude);
  if zone_distance > zone_row.radius_meters then
    raise exception 'Anda berada di luar zona absensi % (jarak % m, batas % m).', zone_row.name, round(zone_distance), round(zone_row.radius_meters);
  end if;
  update public.attendance
  set check_out_at=now(), check_out_client_time=p_client_time, check_out_latitude=p_latitude,
      check_out_longitude=p_longitude, check_out_accuracy_meters=p_accuracy_meters, check_out_selfie_path=p_selfie_path,
      check_out_zone_distance_meters=zone_distance, late_minutes=0, early_leave_minutes=0
  where employee_id=auth.uid() and check_in_date=(now() at time zone 'Asia/Jakarta')::date and check_out_at is null
  returning * into result;
  if not found then raise exception 'Check-in hari ini tidak ditemukan atau check-out sudah dicatat.'; end if;
  return result;
end;
$$;

create or replace function public.admin_correct_attendance(
  p_attendance_id uuid,
  p_check_in_at timestamptz,
  p_check_out_at timestamptz default null,
  p_verification_status text default 'verified',
  p_note text default null
)
returns public.attendance language plpgsql security definer set search_path = public as $$
declare result public.attendance%rowtype;
begin
  if not public.is_super_admin() then raise exception 'Koreksi absensi hanya dapat dilakukan super admin.' using errcode='42501'; end if;
  if p_check_out_at is not null and p_check_out_at < p_check_in_at then raise exception 'Jam pulang tidak boleh sebelum jam masuk.'; end if;
  update public.attendance set check_in_at=p_check_in_at,check_out_at=p_check_out_at,
    check_in_date=(p_check_in_at at time zone 'Asia/Jakarta')::date,verification_status=p_verification_status,
    late_minutes=0,early_leave_minutes=0,note=nullif(trim(p_note),'') where id=p_attendance_id returning * into result;
  if not found then raise exception 'Data absensi tidak ditemukan.'; end if;
  return result;
end;
$$;

notify pgrst, 'reload schema';


-- SOURCE: 20260906_fix_employee_fuel_log.sql

-- Makes employee BBM submissions compatible with the fuel form.
-- Safe to run on databases that already have these columns.
alter table public.fuel_logs add column if not exists fuel_type text;
alter table public.fuel_logs add column if not exists vendor_name text;

-- Employees can submit fuel records only on behalf of their own account.
grant select, insert on public.fuel_logs to authenticated;
drop policy if exists "fuel employee submit" on public.fuel_logs;
create policy "fuel employee submit" on public.fuel_logs
  for insert to authenticated
  with check (employee_id = auth.uid());

-- Refresh PostgREST's schema cache so the new fields are immediately accepted.
notify pgrst, 'reload schema';


-- SOURCE: 20260906_hr_reporting_and_super_admin_corrections.sql

-- HR reporting fields and controlled corrections for the super-admin role.
alter table public.fuel_logs
  add column if not exists validation_status text not null default 'submitted'
    check (validation_status in ('submitted','verified','rejected')),
  add column if not exists validation_note text,
  add column if not exists validated_by uuid references public.profiles(id),
  add column if not exists validated_at timestamptz;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.admin_correct_fuel_log(
  p_fuel_log_id uuid,
  p_previous_odometer numeric,
  p_current_odometer numeric,
  p_liters numeric,
  p_price_per_liter numeric,
  p_validation_status text,
  p_validation_note text default null
)
returns public.fuel_logs language plpgsql security definer set search_path = public as $$
declare result public.fuel_logs%rowtype;
begin
  if not public.is_super_admin() then raise exception 'Koreksi BBM hanya dapat dilakukan super admin.' using errcode='42501'; end if;
  if p_current_odometer < p_previous_odometer or p_liters <= 0 or p_price_per_liter <= 0 then raise exception 'Nilai odometer, liter, atau harga tidak valid.'; end if;
  update public.fuel_logs set previous_odometer=p_previous_odometer,current_odometer=p_current_odometer,
    liters=p_liters,price_per_liter=p_price_per_liter,validation_status=p_validation_status,
    validation_note=nullif(trim(p_validation_note),''),validated_by=auth.uid(),validated_at=now()
  where id=p_fuel_log_id returning * into result;
  if not found then raise exception 'Data pengisian BBM tidak ditemukan.'; end if;
  update public.vehicles set current_odometer=greatest(current_odometer,result.current_odometer) where id=result.vehicle_id;
  return result;
end;
$$;

create or replace function public.admin_correct_attendance(
  p_attendance_id uuid,
  p_check_in_at timestamptz,
  p_check_out_at timestamptz default null,
  p_verification_status text default 'verified',
  p_note text default null
)
returns public.attendance language plpgsql security definer set search_path = public as $$
declare result public.attendance%rowtype;
begin
  if not public.is_super_admin() then raise exception 'Koreksi absensi hanya dapat dilakukan super admin.' using errcode='42501'; end if;
  if p_check_out_at is not null and p_check_out_at < p_check_in_at then raise exception 'Jam pulang tidak boleh sebelum jam masuk.'; end if;
  update public.attendance set check_in_at=p_check_in_at,check_out_at=p_check_out_at,
    check_in_date=(p_check_in_at at time zone 'Asia/Jakarta')::date,verification_status=p_verification_status,
    note=nullif(trim(p_note),'') where id=p_attendance_id returning * into result;
  if not found then raise exception 'Data absensi tidak ditemukan.'; end if;
  return result;
end;
$$;

grant execute on function public.admin_correct_fuel_log(uuid,numeric,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function public.admin_correct_attendance(uuid,timestamptz,timestamptz,text,text) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE: 20260906_operational_reliability.sql

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


-- SOURCE: 20260907_reliable_cash_transaction_entry.sql

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


-- SOURCE: 20260908_vehicle_delete_permission.sql

-- Armada may only be removed by an administrator through the existing RLS policy.
-- The policy `vehicles admin manage` already restricts DELETE to public.is_admin().
grant delete on table public.vehicles to authenticated;
notify pgrst, 'reload schema';


-- SOURCE: 20260910_edit_employee_role_access.sql

-- Super Admin dapat memperbaiki nama, jabatan, dan role akun selain Super Admin lain.
create or replace function public.admin_update_employee_access(
  p_employee_id uuid,
  p_full_name text,
  p_position text,
  p_role text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.profiles%rowtype;
begin
  if not public.is_super_admin() then
    raise exception 'Edit pengguna hanya dapat dilakukan Super Admin.' using errcode='42501';
  end if;
  if p_employee_id = auth.uid() then
    raise exception 'Akun Super Admin aktif tidak dapat diubah dari menu ini.';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Nama lengkap wajib diisi.';
  end if;
  if p_role not in ('employee', 'hr', 'finance') then
    raise exception 'Role yang dipilih tidak valid.';
  end if;

  update public.profiles
  set full_name = trim(p_full_name), position = nullif(trim(p_position), ''), role = p_role
  where id = p_employee_id and role <> 'admin'
  returning * into result;

  if not found then
    raise exception 'Akun tidak ditemukan atau merupakan Super Admin.';
  end if;
  return result;
end;
$$;

grant execute on function public.admin_update_employee_access(uuid,text,text,text) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE: 20260910_fix_attendance_correction_record_id.sql

-- Sertakan ID absensi pada data rekap Admin agar tombol Koreksi mengetahui record yang diedit.
drop function if exists public.admin_attendance_records();

create function public.admin_attendance_records()
returns table (
  id uuid,
  check_in_date date,
  check_in_at timestamptz,
  check_out_at timestamptz,
  verification_status text,
  note text,
  late_minutes integer,
  check_in_zone_distance_meters numeric,
  full_name text,
  employee_position text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Akses absensi administrator diperlukan.';
  end if;

  return query
  select
    a.id, a.check_in_date, a.check_in_at, a.check_out_at,
    a.verification_status, a.note, a.late_minutes,
    a.check_in_zone_distance_meters, p.full_name, p.position
  from public.attendance a
  join public.profiles p on p.id = a.employee_id
  order by a.check_in_date desc, a.check_in_at desc;
end;
$$;

grant execute on function public.admin_attendance_records() to authenticated;
notify pgrst, 'reload schema';


-- SOURCE: 20260910_fuel_efficiency_by_type.sql

-- Acuan konsumsi BBM: Solar 1 L / 7 KM; Pertalite dan jenis lain 1 L / 9 KM.
-- expected_liters adalah kolom turunan agar validasi dan laporan memakai aturan yang sama.
alter table public.fuel_logs drop column if exists expected_liters;

alter table public.fuel_logs add column expected_liters numeric(12,2)
generated always as (
  (current_odometer - previous_odometer) /
  case when lower(trim(coalesce(fuel_type, 'Pertalite'))) = 'solar' then 7.0 else 9.0 end
) stored;

comment on column public.fuel_logs.expected_liters is
  'Estimasi liter berdasarkan jenis BBM: Solar 7 KM/L, Pertalite dan lainnya 9 KM/L.';

notify pgrst, 'reload schema';


-- SOURCE: 20260912_role_permission_boundaries.sql

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


-- SOURCE: 20260913_cash_transaction_bulk_import_and_clear.sql

-- Super Admin can explicitly clear the cash ledger before a controlled replacement import.
create or replace function public.permanently_delete_all_cash_transactions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare removed_count integer;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Hanya Super Admin yang dapat menghapus semua transaksi.' using errcode = '42501';
  end if;
  delete from public.cash_transaction_audits;
  delete from public.cash_transactions;
  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

create or replace function public.import_cash_transactions_batch(p_rows jsonb)
returns table(row_no integer, ok boolean, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  employee_uuid uuid;
  employee_ref text;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'finance')) then
    raise exception 'Hanya Super Admin atau Finance yang dapat mengimpor arus kas.' using errcode = '42501';
  end if;
  for item in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    row_no := coalesce((item->>'row_no')::integer, 0);
    employee_ref := nullif(trim(item->>'employee_reference'), '');
    begin
      if employee_ref ~* '^HMA[0-9]+$' then
        select id into employee_uuid from public.profiles where upper(employee_code) = upper(employee_ref);
        if employee_uuid is null then raise exception 'Kode karyawan % tidak ditemukan.', employee_ref using errcode = '22023'; end if;
      elsif employee_ref is null then
        employee_uuid := null;
      else
        employee_uuid := employee_ref::uuid;
      end if;
      perform public.record_cash_transaction(
        (item->>'transaction_date')::date,
        item->>'type',
        item->>'category',
        item->>'description',
        (item->>'amount')::numeric,
        employee_uuid
      );
      ok := true; error := null;
    exception when others then
      ok := false; error := sqlerrm;
    end;
    return next;
  end loop;
end;
$$;

grant execute on function public.permanently_delete_all_cash_transactions() to authenticated;
grant execute on function public.import_cash_transactions_batch(jsonb) to authenticated;


-- SOURCE: 20260913_cash_transaction_integrity.sql

-- Preserve the financial ledger: no UI action may permanently delete a cash entry.
alter table public.cash_transactions
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

create index if not exists cash_transactions_active_date_idx
  on public.cash_transactions (transaction_date desc, created_at desc)
  where deleted_at is null;

create table if not exists public.cash_transaction_audits (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.cash_transactions(id) on delete restrict,
  action text not null check (action in ('created', 'revised', 'archived', 'restored')),
  old_value jsonb,
  new_value jsonb,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);

alter table public.cash_transaction_audits enable row level security;
grant select on public.cash_transaction_audits to authenticated;
grant all on public.cash_transaction_audits to service_role;

drop policy if exists "cash audit finance admin read" on public.cash_transaction_audits;
create policy "cash audit finance admin read" on public.cash_transaction_audits
  for select to authenticated
  using (exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr', 'finance')
  ));

create or replace function public.audit_cash_transaction_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  audit_action text;
begin
  if tg_op = 'INSERT' then
    audit_action := 'created';
    insert into public.cash_transaction_audits (transaction_id, action, old_value, new_value, changed_by)
    values (new.id, audit_action, null, to_jsonb(new), auth.uid());
    return new;
  end if;

  audit_action := case
    when old.deleted_at is null and new.deleted_at is not null then 'archived'
    when old.deleted_at is not null and new.deleted_at is null then 'restored'
    else 'revised'
  end;
  insert into public.cash_transaction_audits (transaction_id, action, old_value, new_value, changed_by)
  values (new.id, audit_action, to_jsonb(old), to_jsonb(new), auth.uid());
  return new;
end;
$$;

drop trigger if exists cash_transaction_audit_trigger on public.cash_transactions;
create trigger cash_transaction_audit_trigger
  after insert or update on public.cash_transactions
  for each row execute function public.audit_cash_transaction_change();

create or replace function public.revise_cash_transaction(
  p_transaction_id uuid,
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
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'hr', 'finance')) then
    raise exception 'Hanya Admin, HR, atau Finance yang dapat merevisi arus kas.' using errcode = '42501';
  end if;
  if p_transaction_id is null or p_transaction_date is null or p_type not in ('income', 'expense')
     or coalesce(trim(p_category), '') = '' or coalesce(trim(p_description), '') = '' or coalesce(p_amount, 0) <= 0 then
    raise exception 'Data transaksi kas belum lengkap atau nominal tidak valid.' using errcode = '22023';
  end if;
  update public.cash_transactions
  set transaction_date = p_transaction_date, type = p_type, category = trim(p_category),
      description = trim(p_description), amount = p_amount, employee_id = p_employee_id
  where id = p_transaction_id and deleted_at is null
  returning * into result;
  if not found then raise exception 'Transaksi tidak ditemukan atau sudah diarsipkan.' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.archive_cash_transaction(p_transaction_id uuid)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare result public.cash_transactions%rowtype;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'hr', 'finance')) then
    raise exception 'Hanya Admin, HR, atau Finance yang dapat mengarsipkan arus kas.' using errcode = '42501';
  end if;
  update public.cash_transactions set deleted_at = now(), deleted_by = auth.uid()
  where id = p_transaction_id and deleted_at is null
  returning * into result;
  if not found then raise exception 'Transaksi tidak ditemukan atau sudah diarsipkan.' using errcode = 'P0002'; end if;
  return result;
end;
$$;

grant execute on function public.revise_cash_transaction(uuid,date,text,text,text,numeric,uuid) to authenticated;
grant execute on function public.archive_cash_transaction(uuid) to authenticated;
-- The application archives records through the RPC above; raw deletes are prohibited.
revoke delete on table public.cash_transactions from authenticated;


-- SOURCE: 20260913_cash_transaction_permanent_delete.sql

-- Permanent deletion is intentionally limited to Super Admin and always invoked from a confirmed UI action.
create or replace function public.permanently_delete_cash_transactions(p_transaction_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Hanya Super Admin yang dapat menghapus transaksi secara permanen.' using errcode = '42501';
  end if;

  if coalesce(array_length(p_transaction_ids, 1), 0) = 0 then
    raise exception 'Pilih minimal satu transaksi.' using errcode = '22023';
  end if;

  delete from public.cash_transaction_audits where transaction_id = any(p_transaction_ids);
  delete from public.cash_transactions where id = any(p_transaction_ids);
  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

grant execute on function public.permanently_delete_cash_transactions(uuid[]) to authenticated;


-- SOURCE: 20260913_fix_bulk_cash_delete_where_clause.sql

-- Supabase protects DELETE statements without a WHERE clause.  Keep the
-- destructive action inside the restricted Super Admin RPC, but make the
-- target explicit so replacement imports can clear the ledger safely.
create or replace function public.permanently_delete_all_cash_transactions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Hanya Super Admin yang dapat menghapus semua transaksi.' using errcode = '42501';
  end if;

  delete from public.cash_transaction_audits
  where transaction_id is not null;

  delete from public.cash_transactions
  where id is not null;

  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

grant execute on function public.permanently_delete_all_cash_transactions() to authenticated;


-- SOURCE: 20260913_restore_archived_cash_transactions.sql

-- Archived cash transactions remain recoverable by an authorized administrator.
create or replace function public.restore_cash_transaction(p_transaction_id uuid)
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
    raise exception 'Hanya Super Admin, HR, atau Finance yang dapat memulihkan transaksi.' using errcode = '42501';
  end if;

  update public.cash_transactions
  set deleted_at = null,
      deleted_by = null
  where id = p_transaction_id
    and deleted_at is not null
  returning * into result;

  if result.id is null then
    raise exception 'Transaksi arsip tidak ditemukan atau sudah dipulihkan.' using errcode = 'P0002';
  end if;

  return result;
end;
$$;

grant execute on function public.restore_cash_transaction(uuid) to authenticated;


-- SOURCE: 20260918_cash_transaction_employee_options.sql

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
    where p.role in ('employee', 'hr', 'finance')
    order by coalesce(p.employee_code, ''), p.full_name;
end;
$$;

grant execute on function public.cash_transaction_employee_options() to authenticated;


-- SOURCE: 20260918_expand_cash_employee_options.sql

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


-- SOURCE: 20260918_hr_finance_cash_access.sql

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


-- SOURCE: 20260919_company_neutral_employee_reference.sql

-- Employee-code imports must work with the prefix selected by each company.
-- Resolve a visible employee code first; only parse UUID when no code matches.

create or replace function public.import_cash_transactions_batch(p_rows jsonb)
returns table(row_no integer, ok boolean, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  employee_uuid uuid;
  employee_ref text;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'finance')
  ) then
    raise exception 'Hanya Super Admin atau Finance yang dapat mengimpor arus kas.' using errcode = '42501';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    row_no := coalesce((item->>'row_no')::integer, 0);
    employee_ref := nullif(trim(item->>'employee_reference'), '');
    employee_uuid := null;
    begin
      if employee_ref is not null then
        select id into employee_uuid
        from public.profiles
        where upper(employee_code) = upper(employee_ref)
        limit 1;

        if employee_uuid is null then
          begin
            employee_uuid := employee_ref::uuid;
          exception when invalid_text_representation then
            raise exception 'Kode karyawan % tidak ditemukan.', employee_ref using errcode = '22023';
          end;
        end if;
      end if;

      perform public.record_cash_transaction(
        (item->>'transaction_date')::date,
        item->>'type',
        item->>'category',
        item->>'description',
        (item->>'amount')::numeric,
        employee_uuid
      );
      ok := true;
      error := null;
    exception when others then
      ok := false;
      error := sqlerrm;
    end;
    return next;
  end loop;
end;
$$;

grant execute on function public.import_cash_transactions_batch(jsonb) to authenticated;


-- Jalankan SATU KALI pada project Supabase perusahaan baru, sebelum membuat
-- akun karyawan pertama. Ganti semua teks ABS dengan prefix perusahaan.
-- Contoh: PT Contoh Jaya memakai prefix CTJ -> CTJ001, CTJ002, dst.


alter table public.profiles
  drop constraint if exists profiles_employee_code_check;

alter table public.profiles
  add constraint profiles_employee_code_check
  check (employee_code is null or employee_code ~ '^ABS[0-9]{3,}$');

create or replace function public.assign_employee_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'employee' and new.employee_code is null then
    new.employee_code := 'ABS' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
  end if;
  return new;
end;
$$;



notify pgrst, 'reload schema';

commit;

