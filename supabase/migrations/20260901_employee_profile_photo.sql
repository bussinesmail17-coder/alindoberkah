alter table public.profiles add column if not exists avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-avatars', 'employee-avatars', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=3145728, allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "employee avatar upload own" on storage.objects;
drop policy if exists "employee avatar update own" on storage.objects;
drop policy if exists "employee avatar read own or admin" on storage.objects;
drop policy if exists "employee avatar delete own or admin" on storage.objects;
create policy "employee avatar upload own" on storage.objects for insert to authenticated
  with check (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "employee avatar update own" on storage.objects for update to authenticated
  using (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text)
  with check (bucket_id='employee-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "employee avatar read own or admin" on storage.objects for select to authenticated
  using (bucket_id='employee-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));
create policy "employee avatar delete own or admin" on storage.objects for delete to authenticated
  using (bucket_id='employee-avatars' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

drop function if exists public.update_my_profile(text,text);
create function public.update_my_profile(p_full_name text, p_phone text default null, p_avatar_path text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare result public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Sesi karyawan tidak ditemukan.'; end if;
  if char_length(trim(coalesce(p_full_name,''))) < 2 then raise exception 'Nama lengkap minimal 2 karakter.'; end if;
  if p_avatar_path is not null and split_part(p_avatar_path,'/',1) <> auth.uid()::text then
    raise exception 'Lokasi foto profil tidak valid.';
  end if;
  update public.profiles
     set full_name=trim(p_full_name), phone=nullif(trim(coalesce(p_phone,'')), ''), avatar_path=p_avatar_path
   where id=auth.uid()
   returning * into result;
  if not found then raise exception 'Profil karyawan tidak ditemukan.'; end if;
  return result;
end;
$$;

grant execute on function public.update_my_profile(text,text,text) to authenticated;
