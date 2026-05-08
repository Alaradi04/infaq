-- INFAQ security hardening: RLS + user-scoped policies.
-- Apply in Supabase SQL editor or migration pipeline.

alter table if exists public.users enable row level security;
alter table if exists public.transactions enable row level security;
alter table if exists public.goals enable row level security;
alter table if exists public.subscriptions enable row level security;
alter table if exists public.categories enable row level security;
alter table if exists public.notification_preferences enable row level security;

-- USERS (profile)
drop policy if exists users_select_own on public.users;
create policy users_select_own
on public.users for select
using (auth.uid() = id);

drop policy if exists users_insert_own on public.users;
create policy users_insert_own
on public.users for insert
with check (auth.uid() = id);

drop policy if exists users_update_own on public.users;
create policy users_update_own
on public.users for update
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists users_delete_own on public.users;
create policy users_delete_own
on public.users for delete
using (auth.uid() = id);

-- TRANSACTIONS
drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select_own
on public.transactions for select
using (auth.uid() = user_id);

drop policy if exists transactions_insert_own on public.transactions;
create policy transactions_insert_own
on public.transactions for insert
with check (auth.uid() = user_id);

drop policy if exists transactions_update_own on public.transactions;
create policy transactions_update_own
on public.transactions for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists transactions_delete_own on public.transactions;
create policy transactions_delete_own
on public.transactions for delete
using (auth.uid() = user_id);

-- GOALS
drop policy if exists goals_select_own on public.goals;
create policy goals_select_own
on public.goals for select
using (auth.uid() = created_by);

drop policy if exists goals_insert_own on public.goals;
create policy goals_insert_own
on public.goals for insert
with check (auth.uid() = created_by);

drop policy if exists goals_update_own on public.goals;
create policy goals_update_own
on public.goals for update
using (auth.uid() = created_by)
with check (auth.uid() = created_by);

drop policy if exists goals_delete_own on public.goals;
create policy goals_delete_own
on public.goals for delete
using (auth.uid() = created_by);

-- SUBSCRIPTIONS
drop policy if exists subscriptions_select_own on public.subscriptions;
create policy subscriptions_select_own
on public.subscriptions for select
using (auth.uid() = user_id);

drop policy if exists subscriptions_insert_own on public.subscriptions;
create policy subscriptions_insert_own
on public.subscriptions for insert
with check (auth.uid() = user_id);

drop policy if exists subscriptions_update_own on public.subscriptions;
create policy subscriptions_update_own
on public.subscriptions for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists subscriptions_delete_own on public.subscriptions;
create policy subscriptions_delete_own
on public.subscriptions for delete
using (auth.uid() = user_id);

-- CATEGORIES (allow global defaults with user_id null, and user-owned rows)
drop policy if exists categories_select_scoped on public.categories;
create policy categories_select_scoped
on public.categories for select
using (user_id is null or auth.uid() = user_id);

drop policy if exists categories_insert_own on public.categories;
create policy categories_insert_own
on public.categories for insert
with check (auth.uid() = user_id);

drop policy if exists categories_update_own on public.categories;
create policy categories_update_own
on public.categories for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists categories_delete_own on public.categories;
create policy categories_delete_own
on public.categories for delete
using (auth.uid() = user_id);

-- NOTIFICATION PREFERENCES
drop policy if exists notification_preferences_select_own on public.notification_preferences;
create policy notification_preferences_select_own
on public.notification_preferences for select
using (auth.uid() = user_id);

drop policy if exists notification_preferences_insert_own on public.notification_preferences;
create policy notification_preferences_insert_own
on public.notification_preferences for insert
with check (auth.uid() = user_id);

drop policy if exists notification_preferences_update_own on public.notification_preferences;
create policy notification_preferences_update_own
on public.notification_preferences for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists notification_preferences_delete_own on public.notification_preferences;
create policy notification_preferences_delete_own
on public.notification_preferences for delete
using (auth.uid() = user_id);
