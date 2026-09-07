-- Armada may only be removed by an administrator through the existing RLS policy.
-- The policy `vehicles admin manage` already restricts DELETE to public.is_admin().
grant delete on table public.vehicles to authenticated;
notify pgrst, 'reload schema';
