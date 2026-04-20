-- Run this in the Supabase SQL Editor if `user_preferences` does not yet have
-- a `private_review` column.

alter table public.user_preferences
add column if not exists private_review text not null default '';
