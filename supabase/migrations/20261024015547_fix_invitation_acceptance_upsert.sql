-- Use the named uniqueness constraint so the RETURNS TABLE output column
-- `household_id` cannot conflict with the membership column in PL/pgSQL.

create or replace function public.accept_household_invitation(
  p_invitation_token text
)
returns table (
  household_id uuid,
  household_name text,
  membership_role text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  matched_invitation public.household_invitations%rowtype;
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  if p_invitation_token is null or char_length(p_invitation_token) <> 64 then
    raise exception 'invitation is invalid' using errcode = '22023';
  end if;

  select invitation.*
    into matched_invitation
    from public.household_invitations invitation
   where invitation.token_hash = extensions.digest(p_invitation_token, 'sha256')
   for update;

  if matched_invitation.id is null then
    raise exception 'invitation is invalid' using errcode = '22023';
  end if;

  if matched_invitation.status <> 'pending' then
    raise exception 'invitation is no longer available' using errcode = '55000';
  end if;

  if matched_invitation.expires_at <= now() then
    raise exception 'invitation has expired' using errcode = '22023';
  end if;

  if exists (
    select 1
      from public.household_memberships membership
     where membership.user_id = current_user_id
       and membership.status = 'active'
  ) then
    raise exception 'leave the current household before joining another'
      using errcode = '23505';
  end if;

  insert into public.household_memberships (
    household_id,
    user_id,
    role,
    status,
    invited_by,
    joined_at,
    ended_at
  ) values (
    matched_invitation.household_id,
    current_user_id,
    matched_invitation.role,
    'active',
    matched_invitation.created_by,
    now(),
    null
  )
  on conflict on constraint household_memberships_household_user_unique do update
    set role = excluded.role,
        status = 'active',
        invited_by = excluded.invited_by,
        joined_at = now(),
        ended_at = null;

  update public.household_invitations invitation
     set status = 'accepted',
         accepted_by = current_user_id,
         accepted_at = now()
   where invitation.id = matched_invitation.id;

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    subject_user_id,
    invitation_id
  ) values (
    matched_invitation.household_id,
    current_user_id,
    'invitation_accepted',
    current_user_id,
    matched_invitation.id
  );

  return query
  select household.id, household.name, matched_invitation.role
    from public.households household
   where household.id = matched_invitation.household_id;
end;
$$;

revoke all on function public.accept_household_invitation(text)
  from public, anon, authenticated;
grant execute on function public.accept_household_invitation(text)
  to authenticated;
