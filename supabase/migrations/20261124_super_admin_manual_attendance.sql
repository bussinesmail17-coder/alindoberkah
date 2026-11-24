-- Manual attendance entry for Super Admin only.
begin;

create or replace function public.enforce_attendance_server_time()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.selfie_path, '') like 'manual-admin/%' then
    return new;
  end if;
  new.employee_id := auth.uid();
  new.check_in_at := now();
  new.check_in_date := (now() at time zone 'Asia/Jakarta')::date;
  return new;
end;
$$;
create or replace function public.create_super_admin_manual_attendance(
  p_request_id uuid,
  p_employee_id uuid,
  p_check_in_at timestamptz,
  p_check_out_at timestamptz default null,
  p_verification_status text default 'submitted',
  p_note text default null
)
returns public.attendance
language plpgsql security definer set search_path = public
as $$
declare
  result public.attendance%rowtype;
  attendance_date date;
  zone_row public.attendance_zones%rowtype;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Input absensi manual hanya untuk Super Admin.' using errcode='42501';
  end if;
  if p_request_id is null or p_employee_id is null or p_check_in_at is null
    or p_verification_status not in ('submitted','verified','rejected')
    or length(coalesce(p_note,'')) > 500
    or (p_check_out_at is not null and p_check_out_at < p_check_in_at) then
    raise exception 'Data absensi manual tidak valid.' using errcode='22023';
  end if;
  if not exists(select 1 from public.profiles where id=p_employee_id and role='employee') then
    raise exception 'Pilih karyawan yang valid.' using errcode='22023';
  end if;
  attendance_date := (p_check_in_at at time zone 'Asia/Jakarta')::date;
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  select * into result from public.attendance where id=p_request_id;
  if found then return result; end if;
  if exists(select 1 from public.attendance where employee_id=p_employee_id and check_in_date=attendance_date) then
    raise exception 'Absensi karyawan pada tanggal tersebut sudah ada.' using errcode='23505';
  end if;
  select * into zone_row from public.attendance_zones where is_active=true order by created_at desc limit 1;
  insert into public.attendance(
    id,employee_id,check_in_at,client_time,check_in_date,latitude,longitude,accuracy_meters,
    selfie_path,check_out_at,check_out_client_time,check_out_latitude,check_out_longitude,
    shift_name,shift_start_time,shift_end_time,late_minutes,early_leave_minutes,
    verification_status,note
  ) values(
    p_request_id,p_employee_id,p_check_in_at,p_check_in_at,attendance_date,
    coalesce(zone_row.latitude,0),coalesce(zone_row.longitude,0),null,
    'manual-admin/'||p_request_id::text,p_check_out_at,p_check_out_at,
    coalesce(zone_row.latitude,0),coalesce(zone_row.longitude,0),
    'Input manual admin',time '08:00',time '17:00',0,0,
    p_verification_status,coalesce('[INPUT MANUAL SUPER ADMIN] '||trim(p_note),'[INPUT MANUAL SUPER ADMIN]')
  ) returning * into result;
  return result;
end;
$$;
revoke all on function public.create_super_admin_manual_attendance(uuid,uuid,timestamptz,timestamptz,text,text) from public,anon;
grant execute on function public.create_super_admin_manual_attendance(uuid,uuid,timestamptz,timestamptz,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
