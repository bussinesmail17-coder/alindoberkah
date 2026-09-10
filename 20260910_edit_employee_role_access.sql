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
