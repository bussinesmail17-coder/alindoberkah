-- Additive RPC: no changes to courier self-reporting or existing HR RPC.
begin;
create or replace function public.create_super_admin_backup_report(
  p_request_id uuid, p_employee_id uuid, p_report_date date,
  p_title text, p_description text, p_reason text,
  p_success_count integer, p_failed_count integer,
  p_cod_amount numeric, p_dfod_amount numeric, p_evidence_path text default null
)
returns public.employee_reports
language plpgsql security definer set search_path = public as $$
declare
  result public.employee_reports%rowtype;
  report_description text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Input cadangan hanya untuk Super Admin.' using errcode='42501';
  end if;
  if p_request_id is null or p_report_date is null
    or coalesce(trim(p_title),'')='' or length(p_title)>200
    or coalesce(trim(p_reason),'')='' or length(p_reason)>1000
    or length(coalesce(p_description,''))>4000
    or p_success_count is null or p_success_count<0
    or p_failed_count is null or p_failed_count<0
    or p_cod_amount is null or not (p_cod_amount between 0 and 999999999999.99)
    or p_dfod_amount is null or not (p_dfod_amount between 0 and 999999999999.99) then
    raise exception 'Data laporan tidak lengkap atau tidak valid.' using errcode='22023';
  end if;
  if not exists(select 1 from public.profiles where id=p_employee_id and role='employee') then
    raise exception 'Pilih profil kurir / karyawan yang valid.' using errcode='22023';
  end if;
  if p_evidence_path is not null and (
    split_part(p_evidence_path,'/',1) <> auth.uid()::text
    or split_part(p_evidence_path,'/',2) <> 'backup'
    or not exists(select 1 from storage.objects where bucket_id='report-evidence' and name=p_evidence_path)
  ) then
    raise exception 'Bukti laporan tidak valid atau belum diunggah.' using errcode='22023';
  end if;
  report_description := format(E'[INPUT CADANGAN SUPER ADMIN]\nPenginput: %s\nAlasan: %s\nJenis pekerjaan: %s\n%s',
    auth.uid(),trim(p_reason),trim(p_title),coalesce(trim(p_description),''));
  -- Serialize retries, including concurrent requests after a network timeout.
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
  select * into result from public.employee_reports where id=p_request_id;
  if found then
    if result.employee_id=p_employee_id and result.report_date=p_report_date
      and result.title=trim(p_title) and result.description=report_description
      and result.success_count=p_success_count and result.failed_count=p_failed_count
      and result.cod_amount=round(p_cod_amount,2) and result.dfod_amount=round(p_dfod_amount,2)
      and result.evidence_path is not distinct from p_evidence_path then
      return result;
    end if;
    raise exception 'Permintaan ini sudah tersimpan dengan data berbeda. Muat ulang laporan sebelum membuat input baru.' using errcode='22023';
  end if;
  insert into public.employee_reports(id,employee_id,report_date,title,description,success_count,failed_count,cod_amount,dfod_amount,evidence_path,status)
  values(p_request_id,p_employee_id,p_report_date,trim(p_title),report_description,p_success_count,p_failed_count,p_cod_amount,p_dfod_amount,p_evidence_path,'submitted')
  returning * into result;
  return result;
end;
$$;
revoke all on function public.create_super_admin_backup_report(uuid,uuid,date,text,text,text,integer,integer,numeric,numeric,text) from public,anon;
grant execute on function public.create_super_admin_backup_report(uuid,uuid,date,text,text,text,integer,integer,numeric,numeric,text) to authenticated;
notify pgrst, 'reload schema';
commit;
