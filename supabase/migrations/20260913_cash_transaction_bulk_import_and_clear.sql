-- Super Admin can explicitly clear the cash ledger before a controlled replacement import.
create or replace function public.permanently_delete_all_cash_transactions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare removed_count integer;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Hanya Super Admin yang dapat menghapus semua transaksi.' using errcode = '42501';
  end if;
  delete from public.cash_transaction_audits;
  delete from public.cash_transactions;
  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

create or replace function public.import_cash_transactions_batch(p_rows jsonb)
returns table(row_no integer, ok boolean, error text)
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  employee_uuid uuid;
  employee_ref text;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'finance')) then
    raise exception 'Hanya Super Admin atau Finance yang dapat mengimpor arus kas.' using errcode = '42501';
  end if;
  for item in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    row_no := coalesce((item->>'row_no')::integer, 0);
    employee_ref := nullif(trim(item->>'employee_reference'), '');
    begin
      if employee_ref ~* '^HMA[0-9]+$' then
        select id into employee_uuid from public.profiles where upper(employee_code) = upper(employee_ref);
        if employee_uuid is null then raise exception 'Kode karyawan % tidak ditemukan.', employee_ref using errcode = '22023'; end if;
      elsif employee_ref is null then
        employee_uuid := null;
      else
        employee_uuid := employee_ref::uuid;
      end if;
      perform public.record_cash_transaction(
        (item->>'transaction_date')::date,
        item->>'type',
        item->>'category',
        item->>'description',
        (item->>'amount')::numeric,
        employee_uuid
      );
      ok := true; error := null;
    exception when others then
      ok := false; error := sqlerrm;
    end;
    return next;
  end loop;
end;
$$;

grant execute on function public.permanently_delete_all_cash_transactions() to authenticated;
grant execute on function public.import_cash_transactions_batch(jsonb) to authenticated;
