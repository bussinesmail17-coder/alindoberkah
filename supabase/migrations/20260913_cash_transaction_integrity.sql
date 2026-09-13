-- Preserve the financial ledger: no UI action may permanently delete a cash entry.
alter table public.cash_transactions
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

create index if not exists cash_transactions_active_date_idx
  on public.cash_transactions (transaction_date desc, created_at desc)
  where deleted_at is null;

create table if not exists public.cash_transaction_audits (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.cash_transactions(id) on delete restrict,
  action text not null check (action in ('created', 'revised', 'archived', 'restored')),
  old_value jsonb,
  new_value jsonb,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);

alter table public.cash_transaction_audits enable row level security;
grant select on public.cash_transaction_audits to authenticated;
grant all on public.cash_transaction_audits to service_role;

drop policy if exists "cash audit finance admin read" on public.cash_transaction_audits;
create policy "cash audit finance admin read" on public.cash_transaction_audits
  for select to authenticated
  using (exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'hr', 'finance')
  ));

create or replace function public.audit_cash_transaction_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  audit_action text;
begin
  if tg_op = 'INSERT' then
    audit_action := 'created';
    insert into public.cash_transaction_audits (transaction_id, action, old_value, new_value, changed_by)
    values (new.id, audit_action, null, to_jsonb(new), auth.uid());
    return new;
  end if;

  audit_action := case
    when old.deleted_at is null and new.deleted_at is not null then 'archived'
    when old.deleted_at is not null and new.deleted_at is null then 'restored'
    else 'revised'
  end;
  insert into public.cash_transaction_audits (transaction_id, action, old_value, new_value, changed_by)
  values (new.id, audit_action, to_jsonb(old), to_jsonb(new), auth.uid());
  return new;
end;
$$;

drop trigger if exists cash_transaction_audit_trigger on public.cash_transactions;
create trigger cash_transaction_audit_trigger
  after insert or update on public.cash_transactions
  for each row execute function public.audit_cash_transaction_change();

create or replace function public.revise_cash_transaction(
  p_transaction_id uuid,
  p_transaction_date date,
  p_type text,
  p_category text,
  p_description text,
  p_amount numeric,
  p_employee_id uuid default null
)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.cash_transactions%rowtype;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'hr', 'finance')) then
    raise exception 'Hanya Admin, HR, atau Finance yang dapat merevisi arus kas.' using errcode = '42501';
  end if;
  if p_transaction_id is null or p_transaction_date is null or p_type not in ('income', 'expense')
     or coalesce(trim(p_category), '') = '' or coalesce(trim(p_description), '') = '' or coalesce(p_amount, 0) <= 0 then
    raise exception 'Data transaksi kas belum lengkap atau nominal tidak valid.' using errcode = '22023';
  end if;
  update public.cash_transactions
  set transaction_date = p_transaction_date, type = p_type, category = trim(p_category),
      description = trim(p_description), amount = p_amount, employee_id = p_employee_id
  where id = p_transaction_id and deleted_at is null
  returning * into result;
  if not found then raise exception 'Transaksi tidak ditemukan atau sudah diarsipkan.' using errcode = 'P0002'; end if;
  return result;
end;
$$;

create or replace function public.archive_cash_transaction(p_transaction_id uuid)
returns public.cash_transactions
language plpgsql
security definer
set search_path = public
as $$
declare result public.cash_transactions%rowtype;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('admin', 'hr', 'finance')) then
    raise exception 'Hanya Admin, HR, atau Finance yang dapat mengarsipkan arus kas.' using errcode = '42501';
  end if;
  update public.cash_transactions set deleted_at = now(), deleted_by = auth.uid()
  where id = p_transaction_id and deleted_at is null
  returning * into result;
  if not found then raise exception 'Transaksi tidak ditemukan atau sudah diarsipkan.' using errcode = 'P0002'; end if;
  return result;
end;
$$;

grant execute on function public.revise_cash_transaction(uuid,date,text,text,text,numeric,uuid) to authenticated;
grant execute on function public.archive_cash_transaction(uuid) to authenticated;
-- The application archives records through the RPC above; raw deletes are prohibited.
revoke delete on table public.cash_transactions from authenticated;
