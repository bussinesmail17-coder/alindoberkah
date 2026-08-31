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
