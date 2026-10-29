-- Enforce the household lifecycle boundary independently of every command.
-- This closes the race where invitation acceptance and household closure
-- arrive concurrently.

create or replace function private.prevent_closed_household_membership_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active'
     and not exists (
       select 1
         from public.households household
        where household.id = new.household_id
          and household.status = 'active'
     ) then
    raise exception 'closed household cannot activate memberships'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

revoke all on function private.prevent_closed_household_membership_activation()
  from public, anon, authenticated;

create trigger prevent_closed_household_membership_activation
before insert or update of household_id, status
on public.household_memberships
for each row execute function private.prevent_closed_household_membership_activation();

comment on function private.prevent_closed_household_membership_activation() is
  'Prevents any command or concurrent request from activating membership in a closed household.';
