-- Provision the application identity as part of the trusted auth.users insert.
-- The trigger function lives in an unexposed schema and cannot be called by
-- app clients. This replaces the Phase 3 public security-definer RPC.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create index if not exists user_identities_user_id_idx
  on public.user_identities (user_id);

create or replace function private.provision_tenora_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  application_user uuid;
begin
  if exists (
    select 1
      from public.user_identities identity
     where identity.auth_user_id = new.id
  ) then
    return new;
  end if;

  insert into public.tenora_users default values
  returning id into application_user;

  insert into public.user_identities (
    user_id, auth_user_id, provider, provider_subject
  ) values (
    application_user, new.id, 'supabase', new.id::text
  );

  insert into public.account_profiles (user_id)
  values (application_user);

  return new;
end;
$$;

revoke all on function private.provision_tenora_user()
  from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.provision_tenora_user();

-- Provision any identities created between the first migration and this one.
do $$
declare
  auth_user record;
  application_user uuid;
begin
  for auth_user in
    select auth_users.id
      from auth.users auth_users
     where not exists (
       select 1
         from public.user_identities identity
        where identity.auth_user_id = auth_users.id
     )
  loop
    insert into public.tenora_users default values
    returning id into application_user;

    insert into public.user_identities (
      user_id, auth_user_id, provider, provider_subject
    ) values (
      application_user, auth_user.id, 'supabase', auth_user.id::text
    );

    insert into public.account_profiles (user_id)
    values (application_user);
  end loop;
end;
$$;

revoke all on function public.ensure_tenora_user()
  from public, anon, authenticated;
drop function public.ensure_tenora_user();
