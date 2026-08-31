-- Minimal API grants. Row-level security policies still decide which rows/actions are allowed.
grant select on table public.vehicles to authenticated;
grant insert, update on table public.vehicles to authenticated;

grant select, insert on table public.employee_reports to authenticated;
grant update on table public.employee_reports to authenticated;

grant select, insert, update, delete on table public.vehicles to service_role;
grant select, insert, update, delete on table public.employee_reports to service_role;

