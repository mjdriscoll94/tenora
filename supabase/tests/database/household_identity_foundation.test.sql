begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(22);

select extensions.has_table('public', 'households', 'Households table exists');
select extensions.has_table('public', 'household_memberships', 'Household memberships table exists');
select extensions.has_table('public', 'household_invitations', 'Household invitations table exists');
select extensions.has_table('public', 'household_audit_events', 'Household audit table exists');
select extensions.has_index(
  'public',
  'household_memberships',
  'household_memberships_one_active_household_per_user_idx',
  'An adult can belong to only one active household'
);

select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.households'::regclass),
  true,
  'Households use row-level security'
);
select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.household_memberships'::regclass),
  true,
  'Memberships use row-level security'
);
select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.household_invitations'::regclass),
  true,
  'Invitations use row-level security'
);
select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.household_audit_events'::regclass),
  true,
  'Audit events use row-level security'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'authenticated', 'authenticated', 'household-a@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'authenticated', 'authenticated', 'household-b@example.com', '', '{}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","role":"authenticated"}';

insert into public.households (name, created_by)
select 'The Test Household', user_row.id
  from public.tenora_users user_row;

select extensions.is(
  (select count(*)::integer from public.households),
  1,
  'The creator can read their household'
);
select extensions.is(
  (select count(*)::integer
     from public.household_memberships
    where role = 'owner' and status = 'active'),
  1,
  'Creating a household atomically creates its owner membership'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where event_type = 'household_created'),
  1,
  'Creating a household records an audit event'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.household_memberships', 'INSERT'),
  'Clients cannot add household members directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.household_invitations', 'INSERT'),
  'Clients cannot create invitations directly'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.household_audit_events', 'INSERT'),
  'Clients cannot forge household audit events'
);

update public.households
   set name = 'Renamed Test Household';

select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where event_type = 'household_renamed'),
  1,
  'Owners can rename their household and the change is audited'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","role":"authenticated"}';

select extensions.is((select count(*)::integer from public.households), 0, 'Another adult cannot read the household');
select extensions.is((select count(*)::integer from public.household_memberships), 0, 'Another adult cannot read its memberships');
select extensions.is((select count(*)::integer from public.household_invitations), 0, 'Another adult cannot read its invitations');
select extensions.is((select count(*)::integer from public.household_audit_events), 0, 'Another adult cannot read its audit events');

reset role;
select extensions.ok(
  not has_table_privilege('anon', 'public.households', 'SELECT'),
  'Anonymous callers cannot read households'
);
select extensions.hasnt_function(
  'public',
  'current_tenora_user_id',
  array[]::text[],
  'Trusted identity helpers are not exposed in the public API schema'
);

select * from extensions.finish();
rollback;
