-- Step 03: household identity foundation.
--
-- This migration intentionally contains no tasks, habits, schedules, notes,
-- settings, or other personal productivity data. It establishes only the
-- shared household boundary and the adult identities that belong to it.

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null
    check (char_length(btrim(name)) between 1 and 100),
  created_by uuid not null
    references public.tenora_users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_memberships (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households(id) on delete cascade,
  user_id uuid not null
    references public.tenora_users(id) on delete cascade,
  role text not null
    check (role in ('owner', 'admin', 'adult')),
  status text not null default 'active'
    check (status in ('active', 'left', 'revoked')),
  invited_by uuid
    references public.tenora_users(id) on delete set null,
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint household_memberships_household_user_unique
    unique (household_id, user_id),
  constraint household_memberships_end_state_check
    check (
      (status = 'active' and ended_at is null)
      or (status in ('left', 'revoked') and ended_at is not null)
    )
);

-- Tenora 2.0 initially supports one active household per authenticated adult.
-- Keeping this invariant in the database prevents cross-household ambiguity.
create unique index household_memberships_one_active_household_per_user_idx
  on public.household_memberships (user_id)
  where status = 'active';

create index household_memberships_household_access_idx
  on public.household_memberships (household_id, status, user_id);

create index household_memberships_invited_by_idx
  on public.household_memberships (invited_by)
  where invited_by is not null;

create table public.household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null
    references public.households(id) on delete cascade,
  created_by uuid not null
    references public.tenora_users(id) on delete restrict,
  recipient_email text
    check (
      recipient_email is null
      or char_length(recipient_email) between 3 and 320
    ),
  token_hash bytea not null unique,
  role text not null default 'adult'
    check (role in ('admin', 'adult')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  expires_at timestamptz not null,
  accepted_by uuid
    references public.tenora_users(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint household_invitations_expiry_check
    check (expires_at > created_at),
  constraint household_invitations_acceptance_check
    check (
      (status = 'accepted' and accepted_by is not null and accepted_at is not null)
      or (status <> 'accepted' and accepted_by is null and accepted_at is null)
    )
);

create index household_invitations_household_status_idx
  on public.household_invitations (household_id, status, expires_at);

create index household_invitations_created_by_idx
  on public.household_invitations (created_by);

create index household_invitations_accepted_by_idx
  on public.household_invitations (accepted_by)
  where accepted_by is not null;

create unique index household_invitations_pending_email_idx
  on public.household_invitations (household_id, lower(recipient_email))
  where status = 'pending' and recipient_email is not null;

create table public.household_audit_events (
  id bigint generated always as identity primary key,
  household_id uuid not null
    references public.households(id) on delete cascade,
  actor_user_id uuid
    references public.tenora_users(id) on delete set null,
  event_type text not null
    check (event_type in (
      'household_created',
      'household_renamed',
      'invitation_created',
      'invitation_revoked',
      'invitation_accepted',
      'member_role_changed',
      'member_left',
      'member_revoked'
    )),
  subject_user_id uuid
    references public.tenora_users(id) on delete set null,
  invitation_id uuid
    references public.household_invitations(id) on delete set null,
  occurred_at timestamptz not null default now()
);

create index household_audit_events_household_time_idx
  on public.household_audit_events (household_id, occurred_at desc);

create index household_audit_events_actor_idx
  on public.household_audit_events (actor_user_id)
  where actor_user_id is not null;

create index household_audit_events_subject_idx
  on public.household_audit_events (subject_user_id)
  where subject_user_id is not null;

create index household_audit_events_invitation_idx
  on public.household_audit_events (invitation_id)
  where invitation_id is not null;

-- These helpers live outside the exposed API schemas. They derive identity
-- exclusively from auth.uid(); callers can never provide a user identifier.
create or replace function private.current_tenora_user_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_auth_user uuid := (select auth.uid());
  application_user uuid;
begin
  if current_auth_user is null then
    return null;
  end if;

  select identity.user_id
    into application_user
    from public.user_identities identity
   where identity.auth_user_id = current_auth_user;

  return application_user;
end;
$$;

create or replace function private.is_active_household_member(target_household_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
begin
  if (select auth.uid()) is null or current_user_id is null then
    return false;
  end if;

  return exists (
    select 1
      from public.household_memberships membership
     where membership.household_id = target_household_id
       and membership.user_id = current_user_id
       and membership.status = 'active'
  );
end;
$$;

create or replace function private.can_manage_household(target_household_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
begin
  if (select auth.uid()) is null or current_user_id is null then
    return false;
  end if;

  return exists (
    select 1
      from public.household_memberships membership
     where membership.household_id = target_household_id
       and membership.user_id = current_user_id
       and membership.status = 'active'
       and membership.role in ('owner', 'admin')
  );
end;
$$;

create or replace function private.provision_household_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
begin
  if (select auth.uid()) is null
     or current_user_id is null
     or current_user_id <> new.created_by then
    raise exception 'household creator must match the authenticated adult'
      using errcode = '42501';
  end if;

  insert into public.household_memberships (
    household_id,
    user_id,
    role,
    status
  ) values (
    new.id,
    current_user_id,
    'owner',
    'active'
  );

  insert into public.household_audit_events (
    household_id,
    actor_user_id,
    event_type,
    subject_user_id
  ) values (
    new.id,
    current_user_id,
    'household_created',
    current_user_id
  );

  return new;
end;
$$;

create or replace function private.touch_household_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();

  if new.name is distinct from old.name then
    insert into public.household_audit_events (
      household_id,
      actor_user_id,
      event_type
    ) values (
      new.id,
      private.current_tenora_user_id(),
      'household_renamed'
    );
  end if;

  return new;
end;
$$;

revoke all on function private.current_tenora_user_id()
  from public, anon, authenticated;
revoke all on function private.is_active_household_member(uuid)
  from public, anon, authenticated;
revoke all on function private.can_manage_household(uuid)
  from public, anon, authenticated;
revoke all on function private.provision_household_owner()
  from public, anon, authenticated;
revoke all on function private.touch_household_updated_at()
  from public, anon, authenticated;

create trigger on_household_created
after insert on public.households
for each row execute function private.provision_household_owner();

create trigger before_household_updated
before update on public.households
for each row execute function private.touch_household_updated_at();

alter table public.households enable row level security;
alter table public.household_memberships enable row level security;
alter table public.household_invitations enable row level security;
alter table public.household_audit_events enable row level security;

create policy "members can read their household"
on public.households for select to authenticated
using (private.is_active_household_member(id));

create policy "adults can create their household"
on public.households for insert to authenticated
with check (
  created_by = private.current_tenora_user_id()
  and char_length(btrim(name)) between 1 and 100
);

create policy "managers can rename their household"
on public.households for update to authenticated
using (private.can_manage_household(id))
with check (private.can_manage_household(id));

create policy "members can read household memberships"
on public.household_memberships for select to authenticated
using (private.is_active_household_member(household_id));

create policy "managers can read household invitations"
on public.household_invitations for select to authenticated
using (private.can_manage_household(household_id));

create policy "members can read household audit events"
on public.household_audit_events for select to authenticated
using (private.is_active_household_member(household_id));

revoke all on table public.households from public, anon, authenticated;
revoke all on table public.household_memberships from public, anon, authenticated;
revoke all on table public.household_invitations from public, anon, authenticated;
revoke all on table public.household_audit_events from public, anon, authenticated;

grant select on table public.households to authenticated;
grant insert (name, created_by) on table public.households to authenticated;
grant update (name) on table public.households to authenticated;
grant select on table public.household_memberships to authenticated;
grant select on table public.household_invitations to authenticated;
grant select on table public.household_audit_events to authenticated;

comment on table public.households is
  'Shared household identity only; contains no personal productivity data.';
comment on table public.household_memberships is
  'Adult membership and role records for a household.';
comment on table public.household_invitations is
  'Server-managed adult invitation lifecycle; raw invitation tokens are never stored.';
comment on table public.household_audit_events is
  'Immutable security-relevant household membership and invitation events.';
