-- Structured task-result report fields and private photo evidence.
alter table public.employee_reports
  add column if not exists success_count integer not null default 0 check (success_count >= 0),
  add column if not exists failed_count integer not null default 0 check (failed_count >= 0),
  add column if not exists cod_amount numeric(14,2) not null default 0 check (cod_amount >= 0),
  add column if not exists dfod_amount numeric(14,2) not null default 0 check (dfod_amount >= 0),
  add column if not exists evidence_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-evidence',
  'report-evidence',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "employees upload own report evidence" on storage.objects;
create policy "employees upload own report evidence"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'report-evidence'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "employees and admins read report evidence" on storage.objects;
create policy "employees and admins read report evidence"
on storage.objects for select to authenticated
using (
  bucket_id = 'report-evidence'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin()
  )
);

drop policy if exists "employees remove own report evidence" on storage.objects;
create policy "employees remove own report evidence"
on storage.objects for delete to authenticated
using (
  bucket_id = 'report-evidence'
  and (storage.foldername(name))[1] = auth.uid()::text
);
