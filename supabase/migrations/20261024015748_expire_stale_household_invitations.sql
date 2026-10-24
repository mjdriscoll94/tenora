-- Retire stale pending rows before enforcing the one-pending-invite-per-email
-- index. This permits a manager to invite the same address again after expiry.

create or replace function private.expire_stale_household_invitations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.household_invitations invitation
     set status = 'expired'
   where invitation.household_id = new.household_id
     and invitation.status = 'pending'
     and invitation.expires_at <= now();

  return new;
end;
$$;

revoke all on function private.expire_stale_household_invitations()
  from public, anon, authenticated;

create trigger before_household_invitation_created
before insert on public.household_invitations
for each row execute function private.expire_stale_household_invitations();
