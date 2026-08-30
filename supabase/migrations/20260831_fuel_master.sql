-- Jalankan sekali di Supabase SQL Editor untuk mengaktifkan input BBM oleh karyawan.
create table if not exists public.fuel_types (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.fuel_vendors (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.fuel_prices (
  id uuid primary key default gen_random_uuid(), fuel_type_id uuid not null references public.fuel_types(id) on delete restrict,
  vendor_id uuid references public.fuel_vendors(id) on delete set null,
  price_per_liter numeric(12,2) not null check (price_per_liter > 0),
  effective_from date not null default current_date, is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.fuel_logs add column if not exists fuel_type text;
alter table public.fuel_logs add column if not exists vendor_name text;
alter table public.fuel_types enable row level security;
alter table public.fuel_vendors enable row level security;
alter table public.fuel_prices enable row level security;
create policy "fuel masters read authenticated" on public.fuel_types for select using (auth.uid() is not null);
create policy "fuel type admin manage" on public.fuel_types for all using (public.is_admin()) with check (public.is_admin());
create policy "fuel vendors read authenticated" on public.fuel_vendors for select using (auth.uid() is not null);
create policy "fuel vendor admin manage" on public.fuel_vendors for all using (public.is_admin()) with check (public.is_admin());
create policy "fuel prices read authenticated" on public.fuel_prices for select using (auth.uid() is not null);
create policy "fuel price admin manage" on public.fuel_prices for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists "fuel employee submit" on public.fuel_logs;
create policy "fuel employee submit" on public.fuel_logs for insert with check (auth.uid() is not null and employee_id = auth.uid());
insert into public.fuel_types(name) values ('Pertalite'), ('Pertamax'), ('Solar') on conflict (name) do nothing;
