-- Employees may change only their own display name and phone number.
create or replace function public.update_my_profile(p_full_name text, p_phone text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare result public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Sesi karyawan tidak ditemukan.';
  end if;
  if char_length(trim(coalesce(p_full_name,''))) < 2 then
    raise exception 'Nama lengkap minimal 2 karakter.';
  end if;
  update public.profiles
     set full_name = trim(p_full_name),
         phone = nullif(trim(coalesce(p_phone,'')), '')
   where id = auth.uid()
   returning * into result;
  if not found then
    raise exception 'Profil karyawan tidak ditemukan.';
  end if;
  return result;
end;
$$;

grant execute on function public.update_my_profile(text,text) to authenticated;
