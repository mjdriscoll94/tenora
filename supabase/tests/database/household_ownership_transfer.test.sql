begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(30);

select extensions.has_table('public', 'household_ownership_transfers', 'Transfer table exists');
select extensions.has_function('public', 'request_household_ownership_transfer', array['uuid'], 'Request command exists');
select extensions.has_function('public', 'accept_household_ownership_transfer', array['uuid'], 'Accept command exists');
select extensions.has_function('public', 'cancel_household_ownership_transfer', array['uuid'], 'Cancel command exists');
select extensions.has_function('public', 'decline_household_ownership_transfer', array['uuid'], 'Decline command exists');
select extensions.ok(
  not has_function_privilege('anon', 'public.request_household_ownership_transfer(uuid)', 'EXECUTE'),
  'Anonymous callers cannot request a transfer'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.accept_household_ownership_transfer(uuid)', 'EXECUTE'),
  'Anonymous callers cannot accept a transfer'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'a1111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'transfer-owner@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a2222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'transfer-adult@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a3333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'transfer-outsider@example.com', '', '{}', '{}', now(), now());

select set_config('tenora_test.transfer_owner_id', identity.user_id::text, true)
  from public.user_identities identity
 where identity.auth_user_id = 'a1111111-1111-1111-1111-111111111111';
select set_config('tenora_test.transfer_adult_id', identity.user_id::text, true)
  from public.user_identities identity
 where identity.auth_user_id = 'a2222222-2222-2222-2222-222222222222';

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","is_anonymous":false}';
select public.set_household_member_name('Original Owner');
insert into public.households (name, created_by)
select 'Transfer Test Household', identity.user_id
  from public.user_identities identity
 where identity.auth_user_id = 'a1111111-1111-1111-1111-111111111111';
select set_config('tenora_test.transfer_household_id', household.id::text, true)
  from public.households household where household.name = 'Transfer Test Household';
select set_config('tenora_test.transfer_invite', created.invitation_token, true)
  from public.create_household_invitation('transfer-adult@example.com', 'adult', 24) created;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select * from public.accept_household_invitation(
  current_setting('tenora_test.transfer_invite'), 'New Owner'
);

select extensions.throws_ok(
  format(
    'select public.request_household_ownership_transfer(%L::uuid)',
    current_setting('tenora_test.transfer_owner_id')
  ),
  '42501',
  'household owner permission required',
  'A non-owner cannot initiate a transfer'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.request_household_ownership_transfer(
    current_setting('tenora_test.transfer_adult_id')::uuid
  ),
  'The owner can request a transfer to an active adult'
);
select set_config('tenora_test.transfer_id', transfer.id::text, true)
  from public.household_ownership_transfers transfer where transfer.status = 'pending';
select extensions.is(
  (select count(*)::integer from public.household_ownership_transfers where status = 'pending'),
  1,
  'Exactly one transfer is pending'
);
select extensions.throws_ok(
  format(
    'select public.request_household_ownership_transfer(%L::uuid)',
    current_setting('tenora_test.transfer_adult_id')
  ),
  '23505',
  'an ownership transfer is already pending',
  'A second pending transfer is rejected'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a3333333-3333-3333-3333-333333333333","role":"authenticated","is_anonymous":false}';
select extensions.is(
  (select count(*)::integer from public.household_ownership_transfers),
  0,
  'An outsider cannot observe a pending transfer'
);
select extensions.throws_ok(
  format(
    'select public.accept_household_ownership_transfer(%L::uuid)',
    current_setting('tenora_test.transfer_id')
  ),
  '42501',
  'only the recipient can accept this transfer',
  'An outsider cannot accept the transfer'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.accept_household_ownership_transfer(current_setting('tenora_test.transfer_id')::uuid),
  'The recipient can accept the transfer'
);
reset role;
select extensions.is(
  (select role from public.household_memberships membership
    join public.user_identities identity on identity.user_id = membership.user_id
    where identity.auth_user_id = 'a2222222-2222-2222-2222-222222222222'),
  'owner',
  'The recipient becomes owner'
);
select extensions.is(
  (select role from public.household_memberships membership
    join public.user_identities identity on identity.user_id = membership.user_id
    where identity.auth_user_id = 'a1111111-1111-1111-1111-111111111111'),
  'adult',
  'The former owner becomes an adult member'
);

select extensions.is(
  (select count(*)::integer from public.household_memberships
    where household_id = current_setting('tenora_test.transfer_household_id')::uuid
      and status = 'active' and role = 'owner'),
  1,
  'The household still has exactly one active owner'
);
select extensions.is(
  (select status from public.household_ownership_transfers
    where id = current_setting('tenora_test.transfer_id')::uuid),
  'accepted',
  'Acceptance records a terminal transfer state'
);
select extensions.is(
  (select count(*)::integer from public.household_audit_events
    where ownership_transfer_id = current_setting('tenora_test.transfer_id')::uuid
      and event_type in ('ownership_transfer_requested', 'ownership_transfer_accepted')),
  2,
  'Request and acceptance are both audited'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.request_household_ownership_transfer(
    current_setting('tenora_test.transfer_owner_id')::uuid
  ),
  'The new owner can start a later transfer'
);
select set_config('tenora_test.cancel_id', transfer.id::text, true)
  from public.household_ownership_transfers transfer where transfer.status = 'pending';
select extensions.ok(
  public.cancel_household_ownership_transfer(current_setting('tenora_test.cancel_id')::uuid),
  'The requesting owner can cancel'
);
reset role;
select extensions.is(
  (select status from public.household_ownership_transfers
    where id = current_setting('tenora_test.cancel_id')::uuid),
  'cancelled',
  'Cancellation is retained'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select public.request_household_ownership_transfer(
  current_setting('tenora_test.transfer_owner_id')::uuid
);
select set_config('tenora_test.decline_id', transfer.id::text, true)
  from public.household_ownership_transfers transfer where transfer.status = 'pending';
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1111111-1111-1111-1111-111111111111","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.decline_household_ownership_transfer(current_setting('tenora_test.decline_id')::uuid),
  'The recipient can decline'
);
reset role;
select extensions.is(
  (select status from public.household_ownership_transfers
    where id = current_setting('tenora_test.decline_id')::uuid),
  'declined',
  'Decline is retained'
);

select extensions.is(
  (select count(*)::integer from public.household_audit_events
    where household_id = current_setting('tenora_test.transfer_household_id')::uuid
      and event_type = 'ownership_transfer_cancelled'),
  1,
  'Cancellation is audited'
);
select extensions.is(
  (select count(*)::integer from public.household_audit_events
    where household_id = current_setting('tenora_test.transfer_household_id')::uuid
      and event_type = 'ownership_transfer_declined'),
  1,
  'Decline is audited'
);
select extensions.ok(
  (select display_name = 'New Owner' from public.account_profiles profile
    join public.user_identities identity on identity.user_id = profile.user_id
    where identity.auth_user_id = 'a2222222-2222-2222-2222-222222222222'),
  'Invite acceptance saves the required member name'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select public.request_household_ownership_transfer(
  current_setting('tenora_test.transfer_owner_id')::uuid
);
select set_config('tenora_test.expiry_id', transfer.id::text, true)
  from public.household_ownership_transfers transfer where transfer.status = 'pending';
reset role;
update public.household_ownership_transfers
   set created_at = now() - interval '8 days',
       expires_at = now() - interval '1 second'
 where id = current_setting('tenora_test.expiry_id')::uuid;
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select extensions.ok(
  public.expire_household_ownership_transfer(),
  'A stale request expires when household state refreshes'
);
reset role;
select extensions.is(
  (select status from public.household_ownership_transfers
    where id = current_setting('tenora_test.expiry_id')::uuid),
  'expired',
  'The expired terminal state is retained'
);
select extensions.is(
  (select count(*)::integer from public.household_audit_events
    where ownership_transfer_id = current_setting('tenora_test.expiry_id')::uuid
      and event_type = 'ownership_transfer_expired'),
  1,
  'Expiration is audited once'
);

select * from extensions.finish();
rollback;
