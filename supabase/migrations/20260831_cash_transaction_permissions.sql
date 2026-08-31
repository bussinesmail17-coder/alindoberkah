-- Allow authenticated finance/admin users to use cash transactions.
-- Row-level policy public.is_admin() remains the authorization boundary.
grant select, insert, update, delete on table public.cash_transactions to authenticated;
grant select, insert, update, delete on table public.cash_transactions to service_role;
