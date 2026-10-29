begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(13);

select extensions.has_function(
  'public', 'leave_household', array[]::text[],
  'Leave household command exists'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.leave_household()', 'EXECUTE'),
  'Anonymous callers cannot leave a household'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.leave_household()', 'EXECUTE'),
  'Authenticated adults can reach the guarded leave command'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '81818181-8181-8181-8181-818181818181', 'authenticated', 'authenticated', 'leave-owner@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '82828282-8282-8282-8282-828282828282', 'authenticated', 'authenticated', 'leave-adult@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '83838383-8383-8383-8383-838383838383', 'authenticated', 'authenticated', 'leave-outsider@example.com', '', '{}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"81818181-8181-8181-8181-818181818181","role":"authenticated","is_anonymous":false}';

select public.set_household_member_name('Leave Owner');

insert into public.households (name, created_by)
select 'Leave Test Household', user_row.id
  from public.tenora_users user_row;

select set_config('tenora_test.leave_household_id', household.id::text, true)
  from public.households household
 where household.name = 'Leave Test Household';

select set_config('tenora_test.leave_invitation_token', created.invitation_token, true)
  from public.create_household_invitation('leave-adult@example.com', 'adult', 24) created;

select extensions.throws_ok(
  $$ select public.leave_household() $$,
  '42501',
  'household owners must transfer ownership before leaving',
  'The owner cannot orphan the household'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"82828282-8282-8282-8282-828282828282","role":"authenticated","is_anonymous":false}';

select *
  from public.accept_household_invitation(
    current_setting('tenora_test.leave_invitation_token'),
    'Leave Adult'
  );

select extensions.ok(
  public.leave_household(),
  'An adult member can leave the household'
);
select extensions.is(
  (select count(*)::integer from public.households),
  0,
  'The former member immediately loses household access'
);
select extensions.ok(
  not public.leave_household(),
  'Leaving is safely idempotent'
);

reset role;

select extensions.is(
  (select status
     from public.household_memberships membership
     join public.user_identities identity on identity.user_id = membership.user_id
    where identity.auth_user_id = '82828282-8282-8282-8282-828282828282'),
  'left',
  'The membership history records that the adult left'
);
select extensions.ok(
  (select ended_at is not null
     from public.household_memberships membership
     join public.user_identities identity on identity.user_id = membership.user_id
    where identity.auth_user_id = '82828282-8282-8282-8282-828282828282'),
  'The ended timestamp is recorded'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events event
     join public.user_identities identity on identity.user_id = event.subject_user_id
    where event.event_type = 'member_left'
      and identity.auth_user_id = '82828282-8282-8282-8282-828282828282'),
  1,
  'Leaving is recorded in the household audit history'
);
select extensions.is(
  (select count(*)::integer
     from public.households
    where id = current_setting('tenora_test.leave_household_id')::uuid),
  1,
  'The household remains available to its owner'
);
select extensions.is(
  (select count(*)::integer
     from public.household_memberships
    where household_id = current_setting('tenora_test.leave_household_id')::uuid
      and status = 'active'
      and role = 'owner'),
  1,
  'The household retains its active owner'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"83838383-8383-8383-8383-838383838383","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  not public.leave_household(),
  'An adult outside a household receives a safe no-op'
);

select * from extensions.finish();
rollback;
