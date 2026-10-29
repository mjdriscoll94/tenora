begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(20);

select extensions.has_function(
  'public', 'close_household', array[]::text[],
  'Close household command exists'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.close_household()', 'EXECUTE'),
  'Anonymous callers cannot close a household'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.close_household()', 'EXECUTE'),
  'Authenticated adults can reach the guarded close command'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '91919191-9191-9191-9191-919191919191', 'authenticated', 'authenticated', 'close-owner@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '92929292-9292-9292-9292-929292929292', 'authenticated', 'authenticated', 'close-adult@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '93939393-9393-9393-9393-939393939393', 'authenticated', 'authenticated', 'close-outsider@example.com', '', '{}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"91919191-9191-9191-9191-919191919191","role":"authenticated","is_anonymous":false}';

insert into public.households (name, created_by)
select 'Close Test Household', user_row.id
  from public.tenora_users user_row
  join public.user_identities identity on identity.user_id = user_row.id
 where identity.auth_user_id = '91919191-9191-9191-9191-919191919191';

select set_config('tenora_test.close_household_id', household.id::text, true)
  from public.households household
 where household.name = 'Close Test Household';

select set_config('tenora_test.close_join_token', created.invitation_token, true)
  from public.create_household_invitation('close-adult@example.com', 'adult', 24) created;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"92929292-9292-9292-9292-929292929292","role":"authenticated","is_anonymous":false}';

select *
  from public.accept_household_invitation(
    current_setting('tenora_test.close_join_token')
  );

select extensions.throws_ok(
  $$ select public.close_household() $$,
  '42501',
  'household owner permission required',
  'A non-owner cannot close the household'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"91919191-9191-9191-9191-919191919191","role":"authenticated","is_anonymous":false}';

select extensions.throws_ok(
  $$ select public.close_household() $$,
  '55000',
  'other active members must leave before closing the household',
  'The owner cannot close while another adult remains active'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"92929292-9292-9292-9292-929292929292","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.leave_household(),
  'The other adult can leave before closure'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"91919191-9191-9191-9191-919191919191","role":"authenticated","is_anonymous":false}';

select set_config('tenora_test.close_pending_invitation_id', created.invitation_id::text, true)
  from public.create_household_invitation(null, 'adult', 24) created;

select extensions.ok(
  public.close_household(),
  'The sole remaining owner can close the household'
);
select extensions.is(
  (select count(*)::integer from public.households),
  0,
  'The former owner immediately loses active household access'
);
select extensions.ok(
  not public.close_household(),
  'Closing is safely idempotent'
);

reset role;

select extensions.is(
  (select status
     from public.households
    where id = current_setting('tenora_test.close_household_id')::uuid),
  'closed',
  'The household is marked closed rather than deleted'
);
select extensions.ok(
  (select closed_at is not null and closed_by is not null
     from public.households
    where id = current_setting('tenora_test.close_household_id')::uuid),
  'Closure actor and time are retained'
);
select extensions.is(
  (select status
     from public.household_invitations
    where id = current_setting('tenora_test.close_pending_invitation_id')::uuid),
  'revoked',
  'Pending invitations are revoked during closure'
);
select extensions.ok(
  (select status = 'left' and ended_at is not null
     from public.household_memberships membership
     join public.user_identities identity on identity.user_id = membership.user_id
    where membership.household_id = current_setting('tenora_test.close_household_id')::uuid
      and identity.auth_user_id = '91919191-9191-9191-9191-919191919191'),
  'The owner membership is ended without being deleted'
);
select extensions.ok(
  (select status = 'left' and ended_at is not null
     from public.household_memberships membership
     join public.user_identities identity on identity.user_id = membership.user_id
    where membership.household_id = current_setting('tenora_test.close_household_id')::uuid
      and identity.auth_user_id = '92929292-9292-9292-9292-929292929292'),
  'The former adult membership history remains intact'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where household_id = current_setting('tenora_test.close_household_id')::uuid
      and event_type = 'household_closed'),
  1,
  'Closure is recorded in the household audit history'
);
select extensions.is(
  (select count(*)::integer
     from public.households
    where id = current_setting('tenora_test.close_household_id')::uuid),
  1,
  'The household record and history are retained'
);
select extensions.is(
  (select count(*)::integer
     from public.household_memberships
    where household_id = current_setting('tenora_test.close_household_id')::uuid
      and status = 'active'),
  0,
  'No active memberships remain after closure'
);
select extensions.is(
  (select count(*)::integer
     from public.household_memberships
    where household_id = current_setting('tenora_test.close_household_id')::uuid),
  2,
  'All membership records remain available for audit and recovery'
);
select extensions.throws_ok(
  format(
    'update public.household_memberships set status = %L, ended_at = null where household_id = %L and user_id = (select user_id from public.user_identities where auth_user_id = %L)',
    'active',
    current_setting('tenora_test.close_household_id'),
    '92929292-9292-9292-9292-929292929292'
  ),
  '55000',
  'closed household cannot activate memberships',
  'Closed households reject membership reactivation from every code path'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"93939393-9393-9393-9393-939393939393","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  not public.close_household(),
  'An adult outside a household receives a safe no-op'
);

select * from extensions.finish();
rollback;
