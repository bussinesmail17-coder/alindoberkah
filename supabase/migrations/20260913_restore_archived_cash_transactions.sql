-- Archived cash transactions remain recoverable by an authorized administrator.
create or replace function public.restore_cash_transaction(p_transaction_id uuid)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.cash_transactions%rowtype;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr', 'finance')
  ) then
    raise exception 'Hanya Super Admin, HR, atau Finance yang dapat memulihkan transaksi.' using errcode = '42501';
  end if;

  update public.cash_transactions
  set deleted_at = null,
      deleted_by = null
  where id = p_transaction_id
    and deleted_at is not null
  returning * into result;

  if result.id is null then
    raise exception 'Transaksi arsip tidak ditemukan atau sudah dipulihkan.' using errcode = 'P0002';
  end if;

  return result;
end;
$$;

grant execute on function public.restore_cash_transaction(uuid) to authenticated;
