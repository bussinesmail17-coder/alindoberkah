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
