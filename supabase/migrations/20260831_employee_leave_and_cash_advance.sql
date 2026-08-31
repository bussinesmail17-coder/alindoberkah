create table if not exists public.employee_leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('izin','cuti','sakit')),
  start_date date not null,
  end_date date not null,
  note text not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint leave_request_dates check (end_date >= start_date)
);

create table if not exists public.employee_cash_advances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(14,2) not null check (amount > 0),
  note text not null,
  status text not null default 'submitted' check (status in ('submitted','approved','rejected','paid')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now()
);

alter table public.employee_leave_requests enable row level security;
alter table public.employee_cash_advances enable row level security;

create policy "leave requests read own or admin" on public.employee_leave_requests for select using (employee_id = auth.uid() or public.is_admin());
create policy "leave requests employee submit" on public.employee_leave_requests for insert with check (employee_id = auth.uid());
create policy "leave requests admin manage" on public.employee_leave_requests for all using (public.is_admin()) with check (public.is_admin());
create policy "cash advances read own or admin" on public.employee_cash_advances for select using (employee_id = auth.uid() or public.is_admin());
create policy "cash advances employee submit" on public.employee_cash_advances for insert with check (employee_id = auth.uid());
create policy "cash advances admin manage" on public.employee_cash_advances for all using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on public.employee_leave_requests to authenticated;
grant select, insert, update on public.employee_cash_advances to authenticated;
