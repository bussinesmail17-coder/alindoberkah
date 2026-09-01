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
