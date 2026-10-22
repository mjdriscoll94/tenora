-- Phase 3 creates identity only. No task, habit, calendar, household, child,
-- or synchronization data is accepted by this schema.

create table public.tenora_users (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table public.user_identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.tenora_users(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider = 'supabase'),
  provider_subject text not null,
  created_at timestamptz not null default now(),
  constraint user_identities_auth_user_unique unique (auth_user_id),
  constraint user_identities_provider_subject_unique unique (provider, provider_subject)
);

create table public.account_profiles (
  user_id uuid primary key references public.tenora_users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.tenora_users enable row level security;
alter table public.user_identities enable row level security;
alter table public.account_profiles enable row level security;

create policy "adults can read their user row"
on public.tenora_users for select to authenticated
using (
  exists (
    select 1 from public.user_identities identity
    where identity.user_id = tenora_users.id
      and identity.auth_user_id = (select auth.uid())
  )
);

create policy "adults can read their identity"
on public.user_identities for select to authenticated
using (auth_user_id = (select auth.uid()));

create policy "adults can read their account profile"
on public.account_profiles for select to authenticated
using (
  exists (
    select 1 from public.user_identities identity
    where identity.user_id = account_profiles.user_id
      and identity.auth_user_id = (select auth.uid())
  )
);

create policy "adults can update their account profile"
on public.account_profiles for update to authenticated
using (
  exists (
    select 1 from public.user_identities identity
    where identity.user_id = account_profiles.user_id
      and identity.auth_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.user_identities identity
    where identity.user_id = account_profiles.user_id
      and identity.auth_user_id = (select auth.uid())
  )
);

-- The security-definer function is the only client path that can create an
-- application user. It derives identity from auth.uid(), never user_metadata
-- or a caller-provided ID, and uses an empty search_path.
create or replace function public.ensure_tenora_user()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_auth_user uuid := (select auth.uid());
  application_user uuid;
begin
  if current_auth_user is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select identity.user_id
    into application_user
    from public.user_identities identity
   where identity.auth_user_id = current_auth_user;

  if application_user is null then
    begin
      insert into public.tenora_users default values returning id into application_user;
      insert into public.user_identities (
        user_id, auth_user_id, provider, provider_subject
      ) values (
        application_user, current_auth_user, 'supabase', current_auth_user::text
      );
      insert into public.account_profiles (user_id) values (application_user);
    exception when unique_violation then
      select identity.user_id
        into application_user
        from public.user_identities identity
       where identity.auth_user_id = current_auth_user;
    end;
  end if;

  if application_user is null then
    raise exception 'unable to resolve application user';
  end if;
  return application_user;
end;
$$;

revoke all on table public.tenora_users from public, anon;
revoke all on table public.user_identities from public, anon;
revoke all on table public.account_profiles from public, anon;
revoke all on function public.ensure_tenora_user() from public, anon;

grant select on table public.tenora_users to authenticated;
grant select on table public.user_identities to authenticated;
grant select on table public.account_profiles to authenticated;
grant update (display_name) on table public.account_profiles to authenticated;
grant execute on function public.ensure_tenora_user() to authenticated;

comment on table public.tenora_users is 'Provider-independent adult identity; contains no productivity data.';
comment on table public.user_identities is 'Maps the trusted Supabase auth subject to one Tenora adult.';
comment on table public.account_profiles is 'Minimal account metadata only; not a local productivity profile or household membership.';
