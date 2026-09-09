-- Active attendance zone: J&T CARGO TGR215A, Puspitek, Tangerang Selatan.
-- Employees must be within 100 metres of this coordinate to check in or check out.
do $$
declare
  active_zone_id uuid;
begin
  select id into active_zone_id
  from public.attendance_zones
  where is_active
  order by created_at asc
  limit 1;

  if active_zone_id is null then
    insert into public.attendance_zones (name, latitude, longitude, radius_meters, is_active)
    values ('J&T CARGO TGR215A', -6.3467984, 106.7012630, 100, true);
  else
    update public.attendance_zones
    set name = 'J&T CARGO TGR215A',
        latitude = -6.3467984,
        longitude = 106.7012630,
        radius_meters = 100,
        is_active = true,
        updated_at = now()
    where id = active_zone_id;
  end if;
end;
$$;

notify pgrst, 'reload schema';
