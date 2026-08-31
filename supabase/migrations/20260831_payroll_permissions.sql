-- Payroll is created and managed by Admin/HR according to the existing RLS policy.
grant select, insert, update, delete on table public.payroll_records to authenticated;
grant select, insert, update, delete on table public.payroll_records to service_role;
