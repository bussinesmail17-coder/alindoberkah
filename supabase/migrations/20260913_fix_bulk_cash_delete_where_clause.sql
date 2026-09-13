-- Supabase protects DELETE statements without a WHERE clause.  Keep the
-- destructive action inside the restricted Super Admin RPC, but make the
-- target explicit so replacement imports can clear the ledger safely.
create or replace function public.permanently_delete_all_cash_transactions()
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
    raise exception 'Hanya Super Admin yang dapat menghapus semua transaksi.' using errcode = '42501';
  end if;

  delete from public.cash_transaction_audits
  where transaction_id is not null;

  delete from public.cash_transactions
  where id is not null;

  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

grant execute on function public.permanently_delete_all_cash_transactions() to authenticated;
