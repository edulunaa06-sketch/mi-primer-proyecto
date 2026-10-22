-- Now or Never · cuentas y amigos (Supabase)
-- Pega este archivo entero en Supabase › SQL Editor › New query y pulsa Run. Se puede ejecutar más de una vez.
--
-- Qué guarda:
--   profiles         tu nombre de usuario (@usuario) y tu nombre visible
--   follows          quién sigue a quién; la otra persona tiene que aceptar la solicitud
--   daily_summaries  el resumen de cada día que compartes: entrenos (hechos o no), comidas, kcal y pasos
-- Cada persona solo puede escribir lo suyo. Un resumen solo lo ven su dueño y quien le sigue con solicitud aceptada.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,20}$'),
  display_name text not null default '' check (char_length(display_name) <= 40),
  created_at timestamptz not null default now()
);

create table if not exists public.follows (
  follower uuid not null references public.profiles (id) on delete cascade,
  followee uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);

create table if not exists public.daily_summaries (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day date not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, day),
  check (octet_length(data::text) < 20000)
);

create index if not exists follows_followee_idx on public.follows (followee);

alter table public.profiles enable row level security;
alter table public.follows enable row level security;
alter table public.daily_summaries enable row level security;

-- Perfiles: cualquier usuario con sesión puede buscar por @usuario; cada uno edita el suyo.
drop policy if exists "profiles_read" on public.profiles;
create policy "profiles_read" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Seguimiento: ves las solicitudes en las que participas; solo puedes pedir seguir (pendiente);
-- solo la persona seguida puede aceptar; cualquiera de los dos puede borrar la relación.
drop policy if exists "follows_read_own" on public.follows;
create policy "follows_read_own" on public.follows for select to authenticated
  using (follower = auth.uid() or followee = auth.uid());
drop policy if exists "follows_request" on public.follows;
create policy "follows_request" on public.follows for insert to authenticated
  with check (follower = auth.uid() and status = 'pending');
drop policy if exists "follows_accept" on public.follows;
create policy "follows_accept" on public.follows for update to authenticated
  using (followee = auth.uid()) with check (followee = auth.uid());
drop policy if exists "follows_delete" on public.follows;
create policy "follows_delete" on public.follows for delete to authenticated
  using (follower = auth.uid() or followee = auth.uid());

-- Resúmenes diarios: los tuyos y los de quien sigues con solicitud aceptada.
drop policy if exists "summaries_read" on public.daily_summaries;
create policy "summaries_read" on public.daily_summaries for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.follows f
      where f.follower = auth.uid() and f.followee = daily_summaries.user_id and f.status = 'accepted'
    )
  );
drop policy if exists "summaries_insert_own" on public.daily_summaries;
create policy "summaries_insert_own" on public.daily_summaries for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "summaries_update_own" on public.daily_summaries;
create policy "summaries_update_own" on public.daily_summaries for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "summaries_delete_own" on public.daily_summaries;
create policy "summaries_delete_own" on public.daily_summaries for delete to authenticated using (user_id = auth.uid());

-- Al aceptar no se puede cambiar quién sigue a quién (solo el estado).
create or replace function public.follows_only_status_changes() returns trigger language plpgsql as $$
begin
  if new.follower <> old.follower or new.followee <> old.followee then
    raise exception 'Solo se puede cambiar el estado de la solicitud';
  end if;
  return new;
end $$;
drop trigger if exists follows_only_status_changes on public.follows;
create trigger follows_only_status_changes before update on public.follows
  for each row execute function public.follows_only_status_changes();

grant select, insert, update, delete on public.profiles, public.follows, public.daily_summaries to authenticated;
