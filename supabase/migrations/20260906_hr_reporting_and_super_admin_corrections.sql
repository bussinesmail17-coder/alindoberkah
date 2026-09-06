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
