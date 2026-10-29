begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(27);

select extensions.has_function(
  'public', 'create_household_invitation', array['text', 'text', 'integer'],
  'Invitation creation command exists'
);
select extensions.has_function(
  'public', 'preview_household_invitation', array['text'],
  'Invitation preview command exists'
);
select extensions.has_function(
  'public', 'accept_household_invitation', array['text', 'text'],
  'Invitation acceptance command exists'
);
select extensions.has_function(
  'public', 'revoke_household_invitation', array['uuid'],
  'Invitation revocation command exists'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.create_household_invitation(text,text,integer)',
    'EXECUTE'
  ),
  'Anonymous callers cannot create invitations'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.create_household_invitation(text,text,integer)',
    'EXECUTE'
  ),
  'Authenticated adults can reach the guarded invitation command'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '51515151-5151-5151-5151-515151515151', 'authenticated', 'authenticated', 'invite-owner@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '62626262-6262-6262-6262-626262626262', 'authenticated', 'authenticated', 'invite-adult@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '73737373-7373-7373-7373-737373737373', 'authenticated', 'authenticated', 'invite-outsider@example.com', '', '{}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"51515151-5151-5151-5151-515151515151","role":"authenticated","is_anonymous":false}';

select public.set_household_member_name('Invite Owner');

insert into public.households (name, created_by)
select 'Invitation Test Household', user_row.id
  from public.tenora_users user_row;

select set_config('tenora_test.invitation_token', created.invitation_token, true),
       set_config('tenora_test.invitation_id', created.invitation_id::text, true)
  from public.create_household_invitation('Adult@Example.com', 'adult', 24) created;

select extensions.is(
  char_length(current_setting('tenora_test.invitation_token')),
  64,
  'Creation returns a 256-bit hexadecimal token'
);
select extensions.is(
  (select count(*)::integer
     from public.household_invitations
    where status = 'pending' and recipient_email = 'adult@example.com'),
  1,
  'The owner sees one normalized pending invitation'
);
select extensions.is(
  (select octet_length(token_hash)
     from public.household_invitations
    where id = current_setting('tenora_test.invitation_id')::uuid),
  32,
  'Only a SHA-256 token hash is stored'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where event_type = 'invitation_created'),
  1,
  'Invitation creation is audited'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"62626262-6262-6262-6262-626262626262","role":"authenticated","is_anonymous":false}';

select extensions.is(
  (select household_name
     from public.preview_household_invitation(
       current_setting('tenora_test.invitation_token')
     )),
  'Invitation Test Household',
  'A signed-in token holder can preview the household name'
);
select extensions.is(
  (select invited_role
     from public.preview_household_invitation(
       current_setting('tenora_test.invitation_token')
     )),
  'adult',
  'Invitation preview shows the offered role without exposing email'
);

select *
  from public.accept_household_invitation(
    current_setting('tenora_test.invitation_token'),
    'Invite Adult'
  );

select extensions.is(
  (select count(*)::integer from public.households),
  1,
  'The invited adult can read the household after acceptance'
);
select extensions.is(
  (select role
     from public.household_memberships
    where user_id = (select user_id from public.user_identities)),
  'adult',
  'Acceptance creates the offered adult membership'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where event_type = 'invitation_accepted'),
  1,
  'Invitation acceptance is audited'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"73737373-7373-7373-7373-737373737373","role":"authenticated","is_anonymous":false}';

select extensions.is(
  (select count(*)::integer from public.households),
  0,
  'An unrelated adult still cannot read the household'
);
select extensions.throws_ok(
  $$
    select *
      from public.accept_household_invitation(
        current_setting('tenora_test.invitation_token'),
        'Invite Outsider'
      )
  $$,
  '55000',
  'invitation is no longer available',
  'An accepted invitation cannot be consumed a second time'
);
select extensions.throws_ok(
  $$
    select *
      from public.create_household_invitation(null, 'adult', 24)
  $$,
  '42501',
  'household manager permission required',
  'An adult outside a household cannot create invitations'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"51515151-5151-5151-5151-515151515151","role":"authenticated","is_anonymous":false}';

select extensions.is(
  (select status
     from public.household_invitations
    where id = current_setting('tenora_test.invitation_id')::uuid),
  'accepted',
  'The consumed invitation is marked accepted'
);
select extensions.isnt(
  (select encode(token_hash, 'hex')
     from public.household_invitations
    where id = current_setting('tenora_test.invitation_id')::uuid),
  current_setting('tenora_test.invitation_token'),
  'The raw invitation token is not stored'
);

select set_config('tenora_test.revoked_invitation_id', created.invitation_id::text, true),
       set_config('tenora_test.revoked_invitation_token', created.invitation_token, true)
  from public.create_household_invitation(null, 'adult', 24) created;

select extensions.ok(
  public.revoke_household_invitation(
    current_setting('tenora_test.revoked_invitation_id')::uuid
  ),
  'The owner can revoke a pending invitation'
);
select extensions.is(
  (select status
     from public.household_invitations
    where id = current_setting('tenora_test.revoked_invitation_id')::uuid),
  'revoked',
  'A revoked invitation records its terminal state'
);
select extensions.is(
  (select count(*)::integer
     from public.household_audit_events
    where event_type = 'invitation_revoked'),
  1,
  'Invitation revocation is audited'
);
select extensions.is(
  (select invitation_status
     from public.preview_household_invitation(
       current_setting('tenora_test.revoked_invitation_token')
     )),
  'revoked',
  'Preview clearly reports a revoked invitation'
);
select extensions.ok(
  not public.revoke_household_invitation(
    current_setting('tenora_test.revoked_invitation_id')::uuid
  ),
  'Revocation is safely idempotent'
);
select extensions.is(
  (select count(*)::integer
     from public.household_memberships
    where status = 'active'),
  2,
  'The household contains exactly the owner and accepted adult'
);
select extensions.is(
  (select count(*)::integer
     from public.household_invitations
    where accepted_by is not null and accepted_at is not null),
  1,
  'Accepted-by metadata is recorded exactly once'
);

select * from extensions.finish();
rollback;
