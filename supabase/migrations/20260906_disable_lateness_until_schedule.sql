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
