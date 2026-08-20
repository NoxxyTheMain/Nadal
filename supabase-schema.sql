-- NANDAL production schema for Supabase. Run once in Supabase: SQL Editor.
create extension if not exists pgcrypto;
create schema if not exists private;

create type public.swipe_direction as enum ('like', 'pass');
create type public.report_reason as enum ('harassment', 'fake_profile', 'nudity', 'spam', 'underage', 'other');
create type public.moderation_status as enum ('open', 'reviewing', 'resolved', 'dismissed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 40),
  bio text check (char_length(bio) <= 500), city text check (char_length(city) <= 80),
  interests text[] not null default '{}',
  is_discoverable boolean not null default true,
  is_moderator boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.photos (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique, position smallint not null check (position between 0 and 5),
  created_at timestamptz not null default now(), unique(owner_id, position)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id)
);

create table public.swipes (
  actor_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  direction public.swipe_direction not null, created_at timestamptz not null default now(),
  primary key (actor_id, target_id), check (actor_id <> target_id)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(), user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), unique(user_a, user_b), check (user_a < user_b)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(), read_at timestamptz
);
create index messages_match_created on public.messages(match_id, created_at);

create table public.reports (
  id uuid primary key default gen_random_uuid(), reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason public.report_reason not null, details text check (char_length(details) <= 2000),
  status public.moderation_status not null default 'open', created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(), report_id uuid references public.reports(id) on delete set null,
  moderator_id uuid not null references public.profiles(id), action text not null, note text,
  created_at timestamptz not null default now()
);
create table private.rate_limits (
  subject_id uuid not null, action text not null, window_start timestamptz not null,
  count integer not null default 0, primary key(subject_id, action, window_start)
);
revoke all on schema private from public;

create or replace function public.is_blocked(first_user uuid, second_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.blocks where (blocker_id=first_user and blocked_id=second_user) or (blocker_id=second_user and blocked_id=first_user));
$$;
create or replace function public.is_moderator() returns boolean
language sql stable security definer set search_path = public as $$ select exists(select 1 from public.profiles where id=auth.uid() and is_moderator); $$;

create or replace function public.validate_signup_age() returns trigger language plpgsql security definer set search_path = public as $$
declare birthday date;
begin
  begin birthday := (new.raw_user_meta_data->>'birthdate')::date; exception when others then raise exception 'A valid date of birth is required'; end;
  if birthday > current_date - interval '18 years' then raise exception 'NANDAL is for adults aged 18 and over'; end if;
  return new;
end; $$;
create or replace function public.create_profile_for_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name) values (new.id, left(coalesce(new.raw_user_meta_data->>'display_name','Member'),40));
  return new;
end; $$;
create trigger require_adult_before_signup before insert on auth.users for each row execute procedure public.validate_signup_age();
create trigger create_profile_after_signup after insert on auth.users for each row execute procedure public.create_profile_for_new_user();

create or replace function public.enforce_rate_limit(action_name text, limit_count integer) returns boolean
language plpgsql security definer set search_path = public, private as $$
declare bucket timestamptz := date_trunc('minute', now()); current_count integer;
begin
  if auth.uid() is null then return false; end if;
  insert into private.rate_limits(subject_id,action,window_start,count) values(auth.uid(),action_name,bucket,1)
  on conflict(subject_id,action,window_start) do update set count=private.rate_limits.count+1 returning count into current_count;
  return current_count <= limit_count;
end; $$;

create or replace function public.record_swipe(target uuid, choice public.swipe_direction) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); found_match uuid;
begin
  if me is null or target=me then raise exception 'Invalid swipe'; end if;
  if public.is_blocked(me,target) then raise exception 'This profile is unavailable'; end if;
  if not public.enforce_rate_limit('swipe', 60) then raise exception 'Too many swipes. Please wait a minute.'; end if;
  insert into public.swipes(actor_id,target_id,direction) values(me,target,choice) on conflict(actor_id,target_id) do update set direction=excluded.direction,created_at=now();
  if choice='like' and exists(select 1 from public.swipes where actor_id=target and target_id=me and direction='like') then
    insert into public.matches(user_a,user_b) values(least(me,target),greatest(me,target)) on conflict(user_a,user_b) do update set user_a=excluded.user_a returning id into found_match;
  end if;
  return jsonb_build_object('matched', found_match is not null, 'match_id', found_match);
end; $$;

alter table public.profiles enable row level security; alter table public.photos enable row level security; alter table public.blocks enable row level security;
alter table public.swipes enable row level security; alter table public.matches enable row level security; alter table public.messages enable row level security;
alter table public.reports enable row level security; alter table public.moderation_actions enable row level security;
create policy "authenticated users see discoverable profiles" on public.profiles for select to authenticated using (is_discoverable or id=auth.uid() or public.is_moderator());
create policy "users update their profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid() and is_moderator=false);
create policy "owners manage their photos" on public.photos for all to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());
create policy "users see relevant photos" on public.photos for select to authenticated using (owner_id=auth.uid() or exists(select 1 from public.matches where (user_a=auth.uid() and user_b=owner_id) or (user_b=auth.uid() and user_a=owner_id)) or (position=0 and exists(select 1 from public.profiles where id=owner_id and is_discoverable=true) and not public.is_blocked(auth.uid(), owner_id)));
drop policy if exists "users manage their blocks" on public.blocks;
drop policy if exists "users see related blocks" on public.blocks;
create policy "users see related blocks" on public.blocks for select to authenticated using (blocker_id=auth.uid() or blocked_id=auth.uid());
create policy "users insert their blocks" on public.blocks for insert to authenticated with check (blocker_id=auth.uid());
create policy "users update their blocks" on public.blocks for update to authenticated using (blocker_id=auth.uid()) with check (blocker_id=auth.uid());
create policy "users delete their blocks" on public.blocks for delete to authenticated using (blocker_id=auth.uid());
create policy "users see their swipes" on public.swipes for select to authenticated using (actor_id=auth.uid());
create policy "users see their matches" on public.matches for select to authenticated using (user_a=auth.uid() or user_b=auth.uid());
create policy "match members read messages" on public.messages for select to authenticated using (exists(select 1 from public.matches where id=match_id and (user_a=auth.uid() or user_b=auth.uid())));
create policy "match members send messages" on public.messages for insert to authenticated with check (sender_id=auth.uid() and public.enforce_rate_limit('message',20) and exists(select 1 from public.matches where id=match_id and (user_a=auth.uid() or user_b=auth.uid())));
create policy "users create reports" on public.reports for insert to authenticated with check (reporter_id=auth.uid());
create policy "reporters see their reports" on public.reports for select to authenticated using (reporter_id=auth.uid() or public.is_moderator());
create policy "moderators manage reports" on public.reports for update to authenticated using (public.is_moderator()) with check (public.is_moderator());
create policy "moderators see actions" on public.moderation_actions for select to authenticated using (public.is_moderator());
create policy "moderators log actions" on public.moderation_actions for insert to authenticated with check (public.is_moderator() and moderator_id=auth.uid());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('profile-photos','profile-photos',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy "users upload their own photos" on storage.objects for insert to authenticated with check (bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "users update their own photos" on storage.objects for update to authenticated using (bucket_id='profile-photos' and owner_id::text=auth.uid()::text);
create policy "users delete their own photos" on storage.objects for delete to authenticated using (bucket_id='profile-photos' and owner_id::text=auth.uid()::text);
create policy "matches may view photos" on storage.objects for select to authenticated using (bucket_id='profile-photos' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.matches where (user_a=auth.uid() and user_b=(storage.foldername(name))[1]::uuid) or (user_b=auth.uid() and user_a=(storage.foldername(name))[1]::uuid))));
create policy "discover may view primary photos" on storage.objects for select to authenticated using (bucket_id='profile-photos' and exists(select 1 from public.photos ph join public.profiles pr on pr.id=ph.owner_id where ph.storage_path=name and ph.position=0 and pr.is_discoverable=true and not public.is_blocked(auth.uid(), ph.owner_id)));

alter publication supabase_realtime add table public.messages;

-- ============================================================
-- Moderation queue + account deletion additions (run once).
-- Safe to re-run: every statement below is idempotent.
-- ============================================================

alter table public.profiles add column if not exists deleted_at timestamptz;

-- Fix: the original "users update their profile" check forced is_moderator
-- to false on every self-update, which would have blocked moderators from
-- ever editing their own profile. It now just requires the flag be left
-- exactly as it already is — self-promotion is still impossible.
drop policy if exists "users update their profile" on public.profiles;
create policy "users update their profile" on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and is_moderator = (select p.is_moderator from public.profiles p where p.id = auth.uid()));

-- Moderators reviewing a report need to see the reported member's photos
-- even if that member isn't discoverable or matched with the moderator.
drop policy if exists "users see relevant photos" on public.photos;
create policy "users see relevant photos" on public.photos for select to authenticated using (
  owner_id = auth.uid()
  or public.is_moderator()
  or exists (select 1 from public.matches where (user_a = auth.uid() and user_b = owner_id) or (user_b = auth.uid() and user_a = owner_id))
  or (position = 0 and exists (select 1 from public.profiles where id = owner_id and is_discoverable = true) and not public.is_blocked(auth.uid(), owner_id))
);

-- Resolve/dismiss/reopen a report, with an optional moderator note logged
-- to moderation_actions.
create or replace function public.moderator_resolve_report(target_report uuid, new_status public.moderation_status, note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Moderator access required'; end if;
  update public.reports set status = new_status where id = target_report;
  insert into public.moderation_actions(report_id, moderator_id, action, note)
    values (target_report, auth.uid(), 'status:' || new_status::text, nullif(note, ''));
end; $$;

-- Hide (or restore) a reported member's profile from Discover.
create or replace function public.moderator_set_discoverable(target_profile uuid, discoverable boolean, note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Moderator access required'; end if;
  update public.profiles set is_discoverable = discoverable where id = target_profile;
  insert into public.moderation_actions(report_id, moderator_id, action, note)
    values (null, auth.uid(), case when discoverable then 'profile:restored' else 'profile:hidden' end, nullif(note, ''));
end; $$;

-- Self-service account deletion. Scrubs profile fields and marks the
-- account as deleted; the client removes photos beforehand (storage
-- objects can't be touched from a SQL function). Matches/messages are
-- left in place so the other side of a conversation doesn't break, but
-- the deleted member's name now reads "Deleted user" and they disappear
-- from Discover. This cannot remove the underlying login credentials
-- (that requires the Supabase service-role key, which never belongs in
-- client code) — the app now signs the user out and blocks future
-- sign-ins once deleted_at is set; a real credential wipe should be done
-- by an admin via the Supabase dashboard or a trusted server-side job.
create or replace function public.delete_own_account(note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Sign in required'; end if;
  update public.profiles
    set display_name = 'Deleted user', bio = null, city = null, interests = '{}', is_discoverable = false, deleted_at = now()
    where id = me;
end; $$;
