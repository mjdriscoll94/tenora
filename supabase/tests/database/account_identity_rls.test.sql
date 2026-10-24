begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(12);

select has_table('public', 'tenora_users', 'Tenora users table exists');
select has_table('public', 'user_identities', 'Identity mapping table exists');
select has_table('public', 'account_profiles', 'Account profiles table exists');
select has_index('public', 'user_identities', 'user_identities_user_id_idx', 'Identity lookup is indexed');
select has_trigger('auth', 'users', 'on_auth_user_created', 'Auth insert provisions the Tenora identity');
select hasnt_function('public', 'ensure_tenora_user', array[]::text[], 'No privileged identity RPC is exposed');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'authenticated', 'authenticated', 'a@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'authenticated', 'authenticated', 'b@example.com', '', '{}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"authenticated"}';
select is((select count(*)::integer from public.user_identities), 1, 'Adult sees exactly their identity');
select is((select count(*)::integer from public.tenora_users), 1, 'Adult sees exactly their user row');
select is((select count(*)::integer from public.account_profiles), 1, 'Adult sees exactly their account profile');

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","role":"authenticated"}';
select is((select count(*)::integer from public.user_identities), 1, 'RLS hides the other adult identity');
select is((select count(*)::integer from public.tenora_users), 1, 'RLS hides the other adult user row');

reset role;
select ok(
  not has_table_privilege('anon', 'public.user_identities', 'SELECT'),
  'Anonymous callers cannot read identity mappings'
);

select * from finish();
rollback;
