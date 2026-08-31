-- Allow authenticated clients and trusted Edge Functions to reach profiles.
-- Row Level Security policies continue to decide which rows each session can use.
grant usage on schema public to authenticated, service_role;
revoke insert, update, delete on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;
grant usage, select on sequence public.employee_code_seq to service_role;
