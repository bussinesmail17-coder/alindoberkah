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
