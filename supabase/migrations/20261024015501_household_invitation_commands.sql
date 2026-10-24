-- Step 03 controlled invitation lifecycle.
-- Raw invitation tokens are returned once and never persisted. Only their
-- SHA-256 hashes are stored. These RPCs derive the actor from auth.uid() and
-- do not accept caller-supplied user or household identifiers.

create or replace function public.create_household_invitation(
  p_recipient_email text default null,
  p_role text default 'adult',
  p_expires_in_hours integer default 168
)
returns table (
  invitation_id uuid,
  invitation_token text,
  invitation_expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_household_id uuid;
  current_member_role text;
  normalized_email text := nullif(lower(btrim(p_recipient_email)), '');
  requested_role text := lower(btrim(p_role));
  pending_invitation_count integer;
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  if requested_role not in ('admin', 'adult') then
    raise exception 'invitation role must be admin or adult' using errcode = '22023';
  end if;

  if p_expires_in_hours is null or p_expires_in_hours not between 1 and 720 then
    raise exception 'invitation expiry must be between 1 and 720 hours'
      using errcode = '22023';
  end if;

  if normalized_email is not null
     and char_length(normalized_email) not between 3 and 320 then
    raise exception 'recipient email length is invalid' using errcode = '22023';
  end if;

  select membership.household_id, membership.role
    into current_household_id, current_member_role
    from public.household_memberships membership
   where membership.user_id = current_user_id
     and membership.status = 'active'
   for update;

  if current_household_id is null
     or current_member_role not in ('owner', 'admin') then
    raise exception 'household manager permission required' using errcode = '42501';
  end if;

  if requested_role = 'admin' and current_member_role <> 'owner' then
    raise exception 'only a household owner can invite an admin' using errcode = '42501';
  end if;

  select count(*)::integer
    into pending_invitation_count
    from public.household_invitations invitation
   where invitation.household_id = current_household_id
     and invitation.status = 'pending'
     and invitation.expires_at > now();

  if pending_invitation_count >= 20 then
    raise exception 'household has reached the pending invitation limit'
      using errcode = '54000';
  end if;

  invitation_id := gen_random_uuid();
  invitation_token := encode(extensions.gen_random_bytes(32), 'hex');
  invitation_expires_at := now() + make_interval(hours => p_expires_in_hours);

  insert into public.household_invitations (
    id,
    household_id,
    created_by,
    recipient_email,
    token_hash,
    role,
    status,
    expires_at
  ) values (
    invitation_id,
    current_household_id,
    current_user_id,
    normalized_email,
    extensions.digest(invitation_token, 'sha256'),
    requested_role,
    'pending',
    invitation_expires_at
  );

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    invitation_id
  ) values (
    current_household_id,
    current_user_id,
    'invitation_created',
    invitation_id
  );

  return next;
end;
$$;

create or replace function public.preview_household_invitation(
  p_invitation_token text
)
returns table (
  household_name text,
  invited_role text,
  invitation_expires_at timestamptz,
  invitation_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or private.current_tenora_user_id() is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  if p_invitation_token is null or char_length(p_invitation_token) <> 64 then
    return;
  end if;

  return query
  select household.name,
         invitation.role,
         invitation.expires_at,
         case
           when invitation.status = 'pending' and invitation.expires_at <= now()
             then 'expired'
           else invitation.status
         end
    from public.household_invitations invitation
    join public.households household on household.id = invitation.household_id
   where invitation.token_hash = extensions.digest(p_invitation_token, 'sha256');
end;
$$;

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
  on conflict (household_id, user_id) do update
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

create or replace function public.revoke_household_invitation(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  matched_invitation public.household_invitations%rowtype;
  current_member_role text;
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  select invitation.*
    into matched_invitation
    from public.household_invitations invitation
   where invitation.id = p_invitation_id
   for update;

  if matched_invitation.id is null or matched_invitation.status <> 'pending' then
    return false;
  end if;

  select membership.role
    into current_member_role
    from public.household_memberships membership
   where membership.household_id = matched_invitation.household_id
     and membership.user_id = current_user_id
     and membership.status = 'active';

  if current_member_role not in ('owner', 'admin') then
    raise exception 'household manager permission required' using errcode = '42501';
  end if;

  if matched_invitation.role = 'admin' and current_member_role <> 'owner' then
    raise exception 'only a household owner can revoke an admin invitation'
      using errcode = '42501';
  end if;

  update public.household_invitations invitation
     set status = 'revoked'
   where invitation.id = matched_invitation.id;

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    invitation_id
  ) values (
    matched_invitation.household_id,
    current_user_id,
    'invitation_revoked',
    matched_invitation.id
  );

  return true;
end;
$$;

revoke all on function public.create_household_invitation(text, text, integer)
  from public, anon, authenticated;
revoke all on function public.preview_household_invitation(text)
  from public, anon, authenticated;
revoke all on function public.accept_household_invitation(text)
  from public, anon, authenticated;
revoke all on function public.revoke_household_invitation(uuid)
  from public, anon, authenticated;

grant execute on function public.create_household_invitation(text, text, integer)
  to authenticated;
grant execute on function public.preview_household_invitation(text)
  to authenticated;
grant execute on function public.accept_household_invitation(text)
  to authenticated;
grant execute on function public.revoke_household_invitation(uuid)
  to authenticated;

comment on function public.create_household_invitation(text, text, integer) is
  'Creates an expiring household invitation and returns its raw token exactly once.';
comment on function public.preview_household_invitation(text) is
  'Returns non-sensitive household invitation details to a signed-in adult possessing the token.';
comment on function public.accept_household_invitation(text) is
  'Atomically consumes a valid invitation and activates the signed-in adult membership.';
comment on function public.revoke_household_invitation(uuid) is
  'Revokes a pending invitation when called by an authorized household manager.';
