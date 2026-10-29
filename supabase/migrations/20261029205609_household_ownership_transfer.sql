-- Consensual household ownership transfer and household-visible preferred names.
-- Every command derives the actor from auth.uid(); callers cannot impersonate
-- another adult. Transfer transitions lock the request and household so the
-- first committed accept/decline/cancel action wins.

create table public.household_ownership_transfers (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households(id) on delete cascade,
  requested_by uuid not null
    references public.tenora_users(id) on delete restrict,
  recipient_user_id uuid not null
    references public.tenora_users(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'cancelled', 'declined', 'expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint household_ownership_transfers_distinct_adults
    check (requested_by <> recipient_user_id),
  constraint household_ownership_transfers_expiry
    check (expires_at > created_at),
  constraint household_ownership_transfers_resolution
    check (
      (status = 'pending' and resolved_at is null)
      or (status <> 'pending' and resolved_at is not null)
    )
);

create unique index household_ownership_transfers_one_pending_idx
  on public.household_ownership_transfers (household_id)
  where status = 'pending';

create index household_ownership_transfers_recipient_idx
  on public.household_ownership_transfers (recipient_user_id, status, expires_at);

create index household_ownership_transfers_requester_idx
  on public.household_ownership_transfers (requested_by, status, expires_at);

-- At most one active owner can exist. Transactional commands and the deferred
-- invariant trigger below enforce the matching at-least-one rule.
create unique index household_memberships_one_active_owner_idx
  on public.household_memberships (household_id)
  where status = 'active' and role = 'owner';

create or replace function private.enforce_one_active_household_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_household_id uuid := coalesce(new.household_id, old.household_id);
begin
  if exists (
    select 1 from public.households household
     where household.id = affected_household_id and household.status = 'active'
  ) and (
    select count(*) from public.household_memberships membership
     where membership.household_id = affected_household_id
       and membership.status = 'active'
       and membership.role = 'owner'
  ) <> 1 then
    raise exception 'active household must have exactly one owner'
      using errcode = '23514';
  end if;
  return null;
end;
$$;

revoke all on function private.enforce_one_active_household_owner()
  from public, anon, authenticated;

create constraint trigger enforce_one_active_household_owner
after insert or update or delete on public.household_memberships
deferrable initially deferred
for each row execute function private.enforce_one_active_household_owner();

alter table public.household_audit_events
  add column ownership_transfer_id uuid
    references public.household_ownership_transfers(id) on delete set null;

create index household_audit_events_ownership_transfer_idx
  on public.household_audit_events (ownership_transfer_id)
  where ownership_transfer_id is not null;

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
      'member_revoked',
      'ownership_transfer_requested',
      'ownership_transfer_cancelled',
      'ownership_transfer_declined',
      'ownership_transfer_expired',
      'ownership_transfer_accepted'
    ));

create or replace function private.shares_active_household(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.household_memberships mine
      join public.household_memberships other
        on other.household_id = mine.household_id
       and other.user_id = target_user_id
       and other.status = 'active'
     where mine.user_id = private.current_tenora_user_id()
       and mine.status = 'active'
  );
$$;

revoke all on function private.shares_active_household(uuid)
  from public, anon, authenticated;

create policy "household adults can read member names"
on public.account_profiles for select to authenticated
using (private.shares_active_household(user_id));

-- Names are written through a guarded command so normalization and
-- household-local uniqueness cannot be bypassed by a client update.
revoke update (display_name) on table public.account_profiles from authenticated;

create or replace function public.set_household_member_name(p_display_name text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_household_id uuid;
  normalized_name text := btrim(p_display_name);
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  if normalized_name is null or char_length(normalized_name) not between 1 and 100 then
    raise exception 'member name must be between 1 and 100 characters'
      using errcode = '22023';
  end if;

  select membership.household_id
    into current_household_id
    from public.household_memberships membership
   where membership.user_id = current_user_id
     and membership.status = 'active';

  if current_household_id is not null then
    perform 1 from public.households household
     where household.id = current_household_id
     for update;

    if exists (
      select 1
        from public.household_memberships membership
        join public.account_profiles profile on profile.user_id = membership.user_id
       where membership.household_id = current_household_id
         and membership.status = 'active'
         and membership.user_id <> current_user_id
         and lower(btrim(profile.display_name)) = lower(normalized_name)
    ) then
      raise exception 'another household member already uses that name'
        using errcode = '23505';
    end if;
  end if;

  update public.account_profiles profile
     set display_name = normalized_name,
         updated_at = now()
   where profile.user_id = current_user_id;

  return normalized_name;
end;
$$;

revoke all on function public.set_household_member_name(text)
  from public, anon, authenticated;
grant execute on function public.set_household_member_name(text)
  to authenticated;

-- New households require the owner to have a preferred name first.
create or replace function private.provision_household_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_display_name text;
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or current_user_id <> new.created_by then
    raise exception 'household creator must match the authenticated adult'
      using errcode = '42501';
  end if;

  select btrim(profile.display_name)
    into current_display_name
    from public.account_profiles profile
   where profile.user_id = current_user_id;

  if current_display_name is null or current_display_name = '' then
    raise exception 'add your name before creating a household'
      using errcode = '22023';
  end if;

  insert into public.household_memberships (
    household_id, user_id, role, status
  ) values (
    new.id, current_user_id, 'owner', 'active'
  );

  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id
  ) values (
    new.id, current_user_id, 'household_created', current_user_id
  );

  return new;
end;
$$;

-- Invitation acceptance requires and saves the adult's name atomically.
drop function public.accept_household_invitation(text);

create function public.accept_household_invitation(
  p_invitation_token text,
  p_display_name text
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
  normalized_name text := btrim(p_display_name);
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;

  if p_invitation_token is null or char_length(p_invitation_token) <> 64 then
    raise exception 'invitation is invalid' using errcode = '22023';
  end if;

  if normalized_name is null or char_length(normalized_name) not between 1 and 100 then
    raise exception 'member name must be between 1 and 100 characters'
      using errcode = '22023';
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

  perform 1 from public.households household
   where household.id = matched_invitation.household_id
     and household.status = 'active'
   for update;
  if not found then
    raise exception 'household is no longer active' using errcode = '55000';
  end if;

  if exists (
    select 1 from public.household_memberships membership
     where membership.user_id = current_user_id and membership.status = 'active'
  ) then
    raise exception 'leave the current household before joining another'
      using errcode = '23505';
  end if;

  if exists (
    select 1
      from public.household_memberships membership
      join public.account_profiles profile on profile.user_id = membership.user_id
     where membership.household_id = matched_invitation.household_id
       and membership.status = 'active'
       and lower(btrim(profile.display_name)) = lower(normalized_name)
  ) then
    raise exception 'another household member already uses that name'
      using errcode = '23505';
  end if;

  update public.account_profiles profile
     set display_name = normalized_name, updated_at = now()
   where profile.user_id = current_user_id;

  insert into public.household_memberships (
    household_id, user_id, role, status, invited_by, joined_at, ended_at
  ) values (
    matched_invitation.household_id, current_user_id, matched_invitation.role,
    'active', matched_invitation.created_by, now(), null
  )
  on conflict on constraint household_memberships_household_user_unique do update
    set role = excluded.role,
        status = 'active',
        invited_by = excluded.invited_by,
        joined_at = now(),
        ended_at = null;

  update public.household_invitations invitation
     set status = 'accepted', accepted_by = current_user_id, accepted_at = now()
   where invitation.id = matched_invitation.id;

  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, invitation_id
  ) values (
    matched_invitation.household_id, current_user_id, 'invitation_accepted',
    current_user_id, matched_invitation.id
  );

  return query
  select household.id, household.name, matched_invitation.role
    from public.households household
   where household.id = matched_invitation.household_id;
end;
$$;

revoke all on function public.accept_household_invitation(text, text)
  from public, anon, authenticated;
grant execute on function public.accept_household_invitation(text, text)
  to authenticated;

create or replace function private.expire_pending_ownership_transfer(
  target_household_id uuid,
  actor_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_transfer_id uuid;
  expired_recipient_id uuid;
begin
  update public.household_ownership_transfers transfer
     set status = 'expired', resolved_at = now()
   where transfer.household_id = target_household_id
     and transfer.status = 'pending'
     and transfer.expires_at <= now()
  returning transfer.id, transfer.recipient_user_id
       into expired_transfer_id, expired_recipient_id;

  if expired_transfer_id is null then return false; end if;

  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, ownership_transfer_id
  ) values (
    target_household_id, actor_user_id, 'ownership_transfer_expired',
    expired_recipient_id, expired_transfer_id
  );
  return true;
end;
$$;

revoke all on function private.expire_pending_ownership_transfer(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.expire_household_ownership_transfer()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_household_id uuid;
begin
  if (select auth.uid()) is null or current_user_id is null then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;
  select membership.household_id into current_household_id
    from public.household_memberships membership
   where membership.user_id = current_user_id and membership.status = 'active';
  if current_household_id is null then return false; end if;
  perform 1 from public.households household
   where household.id = current_household_id for update;
  return private.expire_pending_ownership_transfer(current_household_id, current_user_id);
end;
$$;

revoke all on function public.expire_household_ownership_transfer()
  from public, anon, authenticated;
grant execute on function public.expire_household_ownership_transfer()
  to authenticated;

create or replace function public.request_household_ownership_transfer(
  p_recipient_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  current_membership public.household_memberships%rowtype;
  recipient_membership public.household_memberships%rowtype;
  transfer_id uuid;
begin
  if (select auth.uid()) is null or current_user_id is null
     or coalesce(((select auth.jwt())->>'is_anonymous')::boolean, false) then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;
  select membership.* into current_membership
    from public.household_memberships membership
   where membership.user_id = current_user_id and membership.status = 'active'
   for update;
  if current_membership.id is null or current_membership.role <> 'owner' then
    raise exception 'household owner permission required' using errcode = '42501';
  end if;
  perform 1 from public.households household
   where household.id = current_membership.household_id and household.status = 'active'
   for update;
  if not found then return false; end if;
  perform private.expire_pending_ownership_transfer(current_membership.household_id, current_user_id);
  if exists (
    select 1 from public.household_ownership_transfers transfer
     where transfer.household_id = current_membership.household_id
       and transfer.status = 'pending'
  ) then
    raise exception 'an ownership transfer is already pending' using errcode = '23505';
  end if;
  select membership.* into recipient_membership
    from public.household_memberships membership
   where membership.household_id = current_membership.household_id
     and membership.user_id = p_recipient_user_id
     and membership.status = 'active'
     and membership.role in ('admin', 'adult')
   for update;
  if recipient_membership.id is null then
    raise exception 'recipient must be an active adult household member'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from public.account_profiles profile
     where profile.user_id in (current_user_id, p_recipient_user_id)
       and nullif(btrim(profile.display_name), '') is null
  ) then
    raise exception 'both adults must add their names before ownership transfer'
      using errcode = '22023';
  end if;
  insert into public.household_ownership_transfers (
    household_id, requested_by, recipient_user_id, expires_at
  ) values (
    current_membership.household_id, current_user_id, p_recipient_user_id,
    now() + interval '7 days'
  ) returning id into transfer_id;
  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, ownership_transfer_id
  ) values (
    current_membership.household_id, current_user_id,
    'ownership_transfer_requested', p_recipient_user_id, transfer_id
  );
  return true;
end;
$$;

create or replace function public.cancel_household_ownership_transfer(p_transfer_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  matched public.household_ownership_transfers%rowtype;
begin
  if (select auth.uid()) is null or current_user_id is null then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;
  select transfer.* into matched from public.household_ownership_transfers transfer
   where transfer.id = p_transfer_id for update;
  if matched.id is null or matched.status <> 'pending' then return false; end if;
  perform 1 from public.households household where household.id = matched.household_id for update;
  if matched.expires_at <= now() then
    return private.expire_pending_ownership_transfer(matched.household_id, current_user_id);
  end if;
  if matched.requested_by <> current_user_id then
    raise exception 'only the requesting owner can cancel this transfer' using errcode = '42501';
  end if;
  update public.household_ownership_transfers set status = 'cancelled', resolved_at = now()
   where id = matched.id;
  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, ownership_transfer_id
  ) values (matched.household_id, current_user_id, 'ownership_transfer_cancelled',
            matched.recipient_user_id, matched.id);
  return true;
end;
$$;

create or replace function public.decline_household_ownership_transfer(p_transfer_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  matched public.household_ownership_transfers%rowtype;
begin
  if (select auth.uid()) is null or current_user_id is null then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;
  select transfer.* into matched from public.household_ownership_transfers transfer
   where transfer.id = p_transfer_id for update;
  if matched.id is null or matched.status <> 'pending' then return false; end if;
  perform 1 from public.households household where household.id = matched.household_id for update;
  if matched.expires_at <= now() then
    return private.expire_pending_ownership_transfer(matched.household_id, current_user_id);
  end if;
  if matched.recipient_user_id <> current_user_id then
    raise exception 'only the recipient can decline this transfer' using errcode = '42501';
  end if;
  update public.household_ownership_transfers set status = 'declined', resolved_at = now()
   where id = matched.id;
  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, ownership_transfer_id
  ) values (matched.household_id, current_user_id, 'ownership_transfer_declined',
            current_user_id, matched.id);
  return true;
end;
$$;

create or replace function public.accept_household_ownership_transfer(p_transfer_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
  matched public.household_ownership_transfers%rowtype;
begin
  if (select auth.uid()) is null or current_user_id is null then
    raise exception 'authenticated adult account required' using errcode = '28000';
  end if;
  select transfer.* into matched from public.household_ownership_transfers transfer
   where transfer.id = p_transfer_id for update;
  if matched.id is null or matched.status <> 'pending' then return false; end if;
  perform 1 from public.households household
   where household.id = matched.household_id and household.status = 'active' for update;
  if not found then return false; end if;
  if matched.expires_at <= now() then
    return private.expire_pending_ownership_transfer(matched.household_id, current_user_id);
  end if;
  if matched.recipient_user_id <> current_user_id then
    raise exception 'only the recipient can accept this transfer' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.household_memberships membership
     where membership.household_id = matched.household_id
       and membership.user_id = matched.requested_by
       and membership.status = 'active' and membership.role = 'owner'
  ) or not exists (
    select 1 from public.household_memberships membership
     where membership.household_id = matched.household_id
       and membership.user_id = matched.recipient_user_id
       and membership.status = 'active' and membership.role in ('admin', 'adult')
  ) then return false;
  end if;

  -- A single UPDATE swaps both roles, so the unique-owner index sees the final
  -- statement result rather than an intermediate two-owner state.
  update public.household_memberships membership
     set role = case
       when membership.user_id = matched.requested_by then 'adult'
       when membership.user_id = matched.recipient_user_id then 'owner'
       else membership.role
     end
   where membership.household_id = matched.household_id
     and membership.status = 'active'
     and membership.user_id in (matched.requested_by, matched.recipient_user_id);

  update public.household_ownership_transfers
     set status = 'accepted', resolved_at = now() where id = matched.id;
  insert into public.household_audit_events (
    household_id, actor_user_id, event_type, subject_user_id, ownership_transfer_id
  ) values (matched.household_id, current_user_id, 'ownership_transfer_accepted',
            current_user_id, matched.id);
  return true;
end;
$$;

revoke all on function public.request_household_ownership_transfer(uuid)
  from public, anon, authenticated;
revoke all on function public.cancel_household_ownership_transfer(uuid)
  from public, anon, authenticated;
revoke all on function public.decline_household_ownership_transfer(uuid)
  from public, anon, authenticated;
revoke all on function public.accept_household_ownership_transfer(uuid)
  from public, anon, authenticated;
grant execute on function public.request_household_ownership_transfer(uuid) to authenticated;
grant execute on function public.cancel_household_ownership_transfer(uuid) to authenticated;
grant execute on function public.decline_household_ownership_transfer(uuid) to authenticated;
grant execute on function public.accept_household_ownership_transfer(uuid) to authenticated;

alter table public.household_ownership_transfers enable row level security;

create policy "participants can read pending ownership transfer"
on public.household_ownership_transfers for select to authenticated
using (
  status = 'pending'
  and private.is_active_household_member(household_id)
  and private.current_tenora_user_id() in (requested_by, recipient_user_id)
);

revoke all on table public.household_ownership_transfers from public, anon, authenticated;
grant select on table public.household_ownership_transfers to authenticated;

comment on table public.household_ownership_transfers is
  'Consent-based, expiring transfer of the single household owner role.';
