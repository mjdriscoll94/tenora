-- Step 04: let the sole remaining owner close a household without deleting
-- the household, membership, invitation, or audit history. Requiring every
-- other adult to leave first prevents one person from unilaterally removing
-- another adult's household access.

alter table public.households
  add column status text not null default 'active',
  add column closed_at timestamptz,
  add column closed_by uuid
    references public.tenora_users(id) on delete set null;

alter table public.households
  add constraint households_status_check
    check (status in ('active', 'closed')),
  add constraint households_closure_state_check
    check (
      (status = 'active' and closed_at is null and closed_by is null)
      or (status = 'closed' and closed_at is not null and closed_by is not null)
    );

create index households_closed_by_idx
  on public.households (closed_by)
  where closed_by is not null;

alter table public.household_audit_events
  drop constraint household_audit_events_event_type_check;

alter table public.household_audit_events
  add constraint household_audit_events_event_type_check
    check (event_type in (
      'household_created',
      'household_renamed',
      'household_closed',
      'invitation_created',
      'invitation_revoked',
      'invitation_accepted',
      'member_role_changed',
      'member_left',
      'member_revoked'
    ));

create or replace function public.close_household()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_membership public.household_memberships%rowtype;
  current_household public.households%rowtype;
  active_member_count integer;
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

  if current_membership.role <> 'owner' then
    raise exception 'household owner permission required' using errcode = '42501';
  end if;

  select household.*
    into current_household
    from public.households household
   where household.id = current_membership.household_id
   for update;

  if current_household.status <> 'active' then
    return false;
  end if;

  select count(*)::integer
    into active_member_count
    from public.household_memberships membership
   where membership.household_id = current_household.id
     and membership.status = 'active';

  if active_member_count <> 1 then
    raise exception 'other active members must leave before closing the household'
      using errcode = '55000';
  end if;

  update public.household_invitations invitation
     set status = 'revoked'
   where invitation.household_id = current_household.id
     and invitation.status = 'pending';

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    subject_user_id
  ) values (
    current_household.id,
    current_user_id,
    'household_closed',
    current_user_id
  );

  update public.households household
     set status = 'closed',
         closed_at = now(),
         closed_by = current_user_id
   where household.id = current_household.id;

  update public.household_memberships membership
     set status = 'left',
         ended_at = now()
   where membership.id = current_membership.id;

  return true;
end;
$$;

revoke all on function public.close_household()
  from public, anon, authenticated;
grant execute on function public.close_household()
  to authenticated;

comment on function public.close_household() is
  'Closes a household only when the authenticated owner is its sole active member, retaining all history.';

comment on column public.households.status is
  'Lifecycle state. Closed households are retained for history and cannot accept new collaboration.';
