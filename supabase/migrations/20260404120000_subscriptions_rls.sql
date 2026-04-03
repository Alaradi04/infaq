-- Row-level security for `subscriptions` so the app can INSERT/SELECT/UPDATE/DELETE
-- rows where user_id = auth.uid(). Fixes: "new row violates row-level security policy" (42501).

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subscriptions_select_own" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriptions_insert_own" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriptions_update_own" ON public.subscriptions;
DROP POLICY IF EXISTS "subscriptions_delete_own" ON public.subscriptions;

CREATE POLICY "subscriptions_select_own"
ON public.subscriptions FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "subscriptions_insert_own"
ON public.subscriptions FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "subscriptions_update_own"
ON public.subscriptions FOR UPDATE TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "subscriptions_delete_own"
ON public.subscriptions FOR DELETE TO authenticated
USING (user_id = auth.uid());
