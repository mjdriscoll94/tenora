-- Keep account profile reads private while avoiding multiple permissive
-- SELECT policies for the authenticated role.
drop policy if exists "adults can read their account profile"
  on public.account_profiles;

drop policy if exists "household adults can read member names"
  on public.account_profiles;

create policy "adults can read their own and household profiles"
on public.account_profiles for select to authenticated
using (
  exists (
    select 1
      from public.user_identities identity
     where identity.user_id = account_profiles.user_id
       and identity.auth_user_id = (select auth.uid())
  )
  or private.shares_active_household(user_id)
);
