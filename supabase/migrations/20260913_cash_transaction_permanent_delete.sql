-- Permanent deletion is intentionally limited to Super Admin and always invoked from a confirmed UI action.
create or replace function public.permanently_delete_cash_transactions(p_transaction_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed_count integer;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Hanya Super Admin yang dapat menghapus transaksi secara permanen.' using errcode = '42501';
  end if;

  if coalesce(array_length(p_transaction_ids, 1), 0) = 0 then
    raise exception 'Pilih minimal satu transaksi.' using errcode = '22023';
  end if;

  delete from public.cash_transaction_audits where transaction_id = any(p_transaction_ids);
  delete from public.cash_transactions where id = any(p_transaction_ids);
  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

grant execute on function public.permanently_delete_cash_transactions(uuid[]) to authenticated;
