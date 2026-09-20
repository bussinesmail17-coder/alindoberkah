-- Employee-code imports must work with the prefix selected by each company.
-- Resolve a visible employee code first; only parse UUID when no code matches.

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
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'finance')
  ) then
    raise exception 'Hanya Super Admin atau Finance yang dapat mengimpor arus kas.' using errcode = '42501';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    row_no := coalesce((item->>'row_no')::integer, 0);
    employee_ref := nullif(trim(item->>'employee_reference'), '');
    employee_uuid := null;
    begin
      if employee_ref is not null then
        select id into employee_uuid
        from public.profiles
        where upper(employee_code) = upper(employee_ref)
        limit 1;

        if employee_uuid is null then
          begin
            employee_uuid := employee_ref::uuid;
          exception when invalid_text_representation then
            raise exception 'Kode karyawan % tidak ditemukan.', employee_ref using errcode = '22023';
          end;
        end if;
      end if;

      perform public.record_cash_transaction(
        (item->>'transaction_date')::date,
        item->>'type',
        item->>'category',
        item->>'description',
        (item->>'amount')::numeric,
        employee_uuid
      );
      ok := true;
      error := null;
    exception when others then
      ok := false;
      error := sqlerrm;
    end;
    return next;
  end loop;
end;
$$;

grant execute on function public.import_cash_transactions_batch(jsonb) to authenticated;
