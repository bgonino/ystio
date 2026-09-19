-- Supabase creates this helper when automatic RLS is enabled. It is only used by
-- internal dashboard automation and must not be callable through the Data API.
revoke all on function public.rls_auto_enable() from public, anon, authenticated;

