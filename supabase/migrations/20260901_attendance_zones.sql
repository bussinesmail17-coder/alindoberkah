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

insert into public.attendance_zones (name, latitude, longitude, radius_meters, is_active)
select 'Tangerang Selatan', -6.2880000, 106.7180000, 22000, true
where not exists (select 1 from public.attendance_zones where is_active);

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
