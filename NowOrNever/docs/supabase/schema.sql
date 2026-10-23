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

-- ============================================================================================
-- Perfil: foto, altura y peso, fotos de progreso y contador de seguidores (versión 2)
-- ============================================================================================

alter table public.profiles add column if not exists avatar_path text check (avatar_path is null or char_length(avatar_path) <= 200);

-- Altura y peso: solo los ven tú y quien te sigue con solicitud aceptada.
create table if not exists public.profile_stats (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  height_cm numeric check (height_cm is null or height_cm between 100 and 250),
  weight_kg numeric check (weight_kg is null or weight_kg between 20 and 400),
  updated_at timestamptz not null default now()
);

-- Fotos de progreso: una por mes y vista (frente, lateral, espalda), con el día en que se hizo.
create table if not exists public.progress_photos (
  user_id uuid not null references public.profiles (id) on delete cascade,
  month text not null check (month ~ '^[0-9]{4}-[0-9]{2}$'),
  view text not null check (view in ('front', 'side', 'back')),
  taken_on date not null,
  path text not null check (char_length(path) <= 200),
  updated_at timestamptz not null default now(),
  primary key (user_id, month, view)
);

alter table public.profile_stats enable row level security;
alter table public.progress_photos enable row level security;

-- ¿Puede la persona con sesión ver los datos de «owner»? (es ella misma o la sigue con solicitud aceptada)
create or replace function public.can_view(owner uuid) returns boolean language sql stable security definer set search_path = public as $$
  select owner = auth.uid() or exists (
    select 1 from public.follows f where f.follower = auth.uid() and f.followee = owner and f.status = 'accepted')
$$;
grant execute on function public.can_view(uuid) to authenticated;

drop policy if exists "stats_read" on public.profile_stats;
create policy "stats_read" on public.profile_stats for select to authenticated using (public.can_view(user_id));
drop policy if exists "stats_write_own" on public.profile_stats;
create policy "stats_write_own" on public.profile_stats for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "photos_read" on public.progress_photos;
create policy "photos_read" on public.progress_photos for select to authenticated using (public.can_view(user_id));
drop policy if exists "photos_write_own" on public.progress_photos;
create policy "photos_write_own" on public.progress_photos for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.profile_stats, public.progress_photos to authenticated;

-- Número de seguidores y seguidos de cualquier perfil (solo los números, no quiénes son).
create or replace function public.follow_counts(target uuid) returns table (followers bigint, following bigint)
language sql stable security definer set search_path = public as $$
  select (select count(*) from public.follows where followee = target and status = 'accepted'),
         (select count(*) from public.follows where follower = target and status = 'accepted')
$$;
grant execute on function public.follow_counts(uuid) to authenticated;

-- Archivos (Supabase Storage): carpetas privadas por persona: avatars/<tu id>/… y progress/<tu id>/…
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', false), ('progress', 'progress', false)
  on conflict (id) do nothing;

drop policy if exists "nn_avatars_read" on storage.objects;
create policy "nn_avatars_read" on storage.objects for select to authenticated using (bucket_id = 'avatars');
drop policy if exists "nn_progress_read" on storage.objects;
create policy "nn_progress_read" on storage.objects for select to authenticated
  using (bucket_id = 'progress' and public.can_view(((storage.foldername(name))[1])::uuid));
drop policy if exists "nn_own_insert" on storage.objects;
create policy "nn_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'progress') and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "nn_own_update" on storage.objects;
create policy "nn_own_update" on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'progress') and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id in ('avatars', 'progress') and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "nn_own_delete" on storage.objects;
create policy "nn_own_delete" on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'progress') and (storage.foldername(name))[1] = auth.uid()::text);

-- Versión 3: encontrar a tus contactos por número de teléfono.
-- Se guarda un resumen (hash SHA-256) del número, nunca el número. Nadie puede leer esta tabla directamente:
-- solo se usa con las dos funciones de abajo, que devuelven perfiles cuyos números ya tienes en tu agenda.
create table if not exists public.profile_phones (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  phone_hash text not null unique check (phone_hash ~ '^[0-9a-f]{64}$')
);
alter table public.profile_phones enable row level security;
revoke all on public.profile_phones from anon, authenticated;

-- Guarda (o borra, con null) el resumen de TU número.
create or replace function public.set_my_phone(hash text) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if hash is null then
    delete from public.profile_phones where user_id = auth.uid();
  else
    insert into public.profile_phones (user_id, phone_hash) values (auth.uid(), hash)
      on conflict (user_id) do update set phone_hash = excluded.phone_hash;
  end if;
end $$;

-- Perfiles cuyos números están entre los de tu agenda (máximo 2000 por consulta). Tú no sales.
create or replace function public.find_by_phones(hashes text[]) returns setof public.profiles
language sql stable security definer set search_path = public as $$
  select p.* from public.profiles p
  join public.profile_phones ph on ph.user_id = p.id
  where auth.uid() is not null and p.id <> auth.uid() and ph.phone_hash = any (hashes[1:2000])
$$;
revoke all on function public.set_my_phone(text) from public, anon;
revoke all on function public.find_by_phones(text[]) from public, anon;
grant execute on function public.set_my_phone(text) to authenticated;
grant execute on function public.find_by_phones(text[]) to authenticated;
