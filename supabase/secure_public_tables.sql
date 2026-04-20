-- Run this in the Supabase SQL Editor.
-- This script closes anonymous access to public tables and enables strict RLS.

begin;

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.user_preferences from anon;

drop policy if exists "Allow public read access to profiles for login check" on public.profiles;
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_delete_own" on public.profiles;

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (auth.uid() = id);

create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create policy "profiles_delete_own"
on public.profiles
for delete
to authenticated
using (auth.uid() = id);

drop policy if exists "prefs_select_own" on public.user_preferences;
drop policy if exists "prefs_insert_own" on public.user_preferences;
drop policy if exists "prefs_update_own" on public.user_preferences;
drop policy if exists "prefs_delete_own" on public.user_preferences;

create policy "prefs_select_own"
on public.user_preferences
for select
to authenticated
using (auth.uid() = user_uuid);

create policy "prefs_insert_own"
on public.user_preferences
for insert
to authenticated
with check (auth.uid() = user_uuid);

create policy "prefs_update_own"
on public.user_preferences
for update
to authenticated
using (auth.uid() = user_uuid)
with check (auth.uid() = user_uuid);

create policy "prefs_delete_own"
on public.user_preferences
for delete
to authenticated
using (auth.uid() = user_uuid);

commit;
