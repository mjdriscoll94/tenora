-- Step 04: allow an adult or admin to leave a household without deleting
-- household history or any private personal data. Owners remain responsible
-- for transferring ownership before they can leave.

create or replace function public.leave_household()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_membership public.household_memberships%rowtype;
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  select membership.*
    into current_membership
    from public.household_memberships membership
   where membership.user_id = current_user_id
     and membership.status = 'active'
   for update;

  if current_membership.id is null then
    return false;
  end if;

  if current_membership.role = 'owner' then
    raise exception 'household owners must transfer ownership before leaving'
      using errcode = '42501';
  end if;

  update public.household_memberships membership
     set status = 'left',
         ended_at = now()
   where membership.id = current_membership.id;

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    subject_user_id
  ) values (
    current_membership.household_id,
    current_user_id,
    'member_left',
    current_user_id
  );

  return true;
end;
$$;

revoke all on function public.leave_household()
  from public, anon, authenticated;
grant execute on function public.leave_household()
  to authenticated;

comment on function public.leave_household() is
  'Ends the authenticated non-owner adult membership while preserving household and audit history.';
