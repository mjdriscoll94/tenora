-- RLS expressions execute with the calling database role and therefore need
-- EXECUTE on the three read-only policy helpers. The private schema itself
-- remains inaccessible to authenticated clients and is not API-exposed, so
-- these functions cannot be invoked directly through PostgREST.

grant execute on function private.current_tenora_user_id()
  to authenticated;
grant execute on function private.is_active_household_member(uuid)
  to authenticated;
grant execute on function private.can_manage_household(uuid)
  to authenticated;

revoke all on function private.provision_household_owner()
  from public, anon, authenticated;
revoke all on function private.touch_household_updated_at()
  from public, anon, authenticated;
