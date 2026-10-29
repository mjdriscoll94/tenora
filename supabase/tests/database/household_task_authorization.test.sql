begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select extensions.plan(30);

select extensions.has_table('public', 'household_tasks', 'Household task table exists');
select extensions.has_table('public', 'household_task_events', 'Household task history exists');
select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.household_tasks'::regclass),
  true,
  'Household tasks use row-level security'
);
select extensions.is(
  (select relrowsecurity from pg_class where oid = 'public.household_task_events'::regclass),
  true,
  'Household task history uses row-level security'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.household_tasks', 'SELECT'),
  'Anonymous callers cannot read household tasks'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.household_tasks', 'DELETE'),
  'Clients cannot hard-delete household tasks'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.household_task_events', 'INSERT'),
  'Clients cannot forge household task history'
);
select extensions.ok(
  not has_column_privilege('authenticated', 'public.household_tasks', 'household_id', 'UPDATE'),
  'Clients cannot move a task to another household'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'b1111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'task-owner@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b2222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'task-adult@example.com', '', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b3333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'task-outsider@example.com', '', '{}', '{}', now(), now());

select set_config('tenora_test.task_owner_id', identity.user_id::text, true)
  from public.user_identities identity
 where identity.auth_user_id = 'b1111111-1111-1111-1111-111111111111';
select set_config('tenora_test.task_adult_id', identity.user_id::text, true)
  from public.user_identities identity
 where identity.auth_user_id = 'b2222222-2222-2222-2222-222222222222';
select set_config('tenora_test.task_outsider_id', identity.user_id::text, true)
  from public.user_identities identity
 where identity.auth_user_id = 'b3333333-3333-3333-3333-333333333333';

set local role authenticated;
set local request.jwt.claims = '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated","is_anonymous":false}';
select public.set_household_member_name('Task Owner');
insert into public.households (name, created_by)
values ('Task Authorization Household', current_setting('tenora_test.task_owner_id')::uuid);
select set_config('tenora_test.task_household_id', household.id::text, true)
  from public.households household where household.name = 'Task Authorization Household';
select set_config('tenora_test.task_invite', created.invitation_token, true)
  from public.create_household_invitation('task-adult@example.com', 'adult', 24) created;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select * from public.accept_household_invitation(
  current_setting('tenora_test.task_invite'), 'Task Adult'
);

insert into public.household_tasks (
  household_id,
  title,
  notes,
  priority,
  assigned_to
) values (
  current_setting('tenora_test.task_household_id')::uuid,
  '  Buy groceries  ',
  'Shared household list',
  'important',
  current_setting('tenora_test.task_adult_id')::uuid
);
select set_config('tenora_test.shared_task_id', task.id::text, true)
  from public.household_tasks task where task.title = 'Buy groceries';

select extensions.is(
  (select count(*)::integer from public.household_tasks),
  1,
  'An active adult can create a household task'
);
select extensions.is(
  (select created_by from public.household_tasks limit 1),
  current_setting('tenora_test.task_adult_id')::uuid,
  'The database records the authenticated creator'
);
select extensions.is(
  (select count(*)::integer from public.household_task_events where event_type = 'task_created'),
  1,
  'Creation appends immutable task history'
);

update public.household_tasks
   set status = 'completed'
 where id = current_setting('tenora_test.shared_task_id')::uuid;

select extensions.is(
  (select completed_by from public.household_tasks where id = current_setting('tenora_test.shared_task_id')::uuid),
  current_setting('tenora_test.task_adult_id')::uuid,
  'The database records the authenticated completion actor'
);
select extensions.is(
  (select version::integer from public.household_tasks where id = current_setting('tenora_test.shared_task_id')::uuid),
  2,
  'Each accepted task mutation advances its version'
);
select extensions.is(
  (select count(*)::integer from public.household_task_events where event_type = 'task_completed'),
  1,
  'Completion appends immutable task history'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated","is_anonymous":false}';
select extensions.is(
  (select count(*)::integer from public.household_tasks),
  1,
  'Another active household adult can read the shared task'
);
select extensions.is(
  (select count(*)::integer from public.household_task_events),
  2,
  'Another active household adult can read task history'
);

select extensions.throws_ok(
  format(
    'update public.household_tasks set assigned_to = %L::uuid where id = %L::uuid',
    current_setting('tenora_test.task_outsider_id'),
    current_setting('tenora_test.shared_task_id')
  ),
  '23514',
  'assignee must be an active household member',
  'A task cannot be assigned outside its household'
);

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b3333333-3333-3333-3333-333333333333","role":"authenticated","is_anonymous":false}';
select extensions.is(
  (select count(*)::integer from public.household_tasks),
  0,
  'An unrelated adult cannot read household tasks'
);
select extensions.is(
  (select count(*)::integer from public.household_task_events),
  0,
  'An unrelated adult cannot read household task history'
);
select extensions.throws_ok(
  format(
    'insert into public.household_tasks (household_id, title) values (%L::uuid, %L)',
    current_setting('tenora_test.task_household_id'),
    'Unauthorized task'
  ),
  '42501',
  'active household membership required',
  'An unrelated adult cannot create a task in the household'
);

select public.set_household_member_name('Other Household Owner');
insert into public.households (name, created_by)
values ('Other Task Household', current_setting('tenora_test.task_outsider_id')::uuid);
select set_config('tenora_test.other_task_household_id', household.id::text, true)
  from public.households household where household.name = 'Other Task Household';
insert into public.household_tasks (household_id, title)
values (current_setting('tenora_test.other_task_household_id')::uuid, 'Other household task');

select extensions.is(
  (select count(*)::integer from public.household_tasks),
  1,
  'An adult sees only tasks from their active household'
);

update public.household_tasks
   set title = 'Cross-household edit'
 where id = current_setting('tenora_test.shared_task_id')::uuid;

reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"b2222222-2222-2222-2222-222222222222","role":"authenticated","is_anonymous":false}';
select extensions.ok(public.leave_household(), 'The adult can leave the household');
select extensions.is(
  (select count(*)::integer from public.household_tasks),
  0,
  'A former member immediately loses task access'
);
select extensions.is(
  (select count(*)::integer from public.household_task_events),
  0,
  'A former member immediately loses task-history access'
);
update public.household_tasks
   set title = 'No longer authorized'
 where id = current_setting('tenora_test.shared_task_id')::uuid;

reset role;
select extensions.is(
  (select count(*)::integer
     from public.household_task_events
    where task_id = current_setting('tenora_test.shared_task_id')::uuid),
  2,
  'Task history remains after a member leaves'
);
select extensions.is(
  (select count(*)::integer
     from public.household_tasks
    where id = current_setting('tenora_test.shared_task_id')::uuid),
  1,
  'The shared task remains after a member leaves'
);
select extensions.is(
  (select status from public.household_tasks where id = current_setting('tenora_test.shared_task_id')::uuid),
  'completed',
  'Leaving does not change shared task state'
);
select extensions.is(
  (select title from public.household_tasks where id = current_setting('tenora_test.shared_task_id')::uuid),
  'Buy groceries',
  'A cross-household update cannot change task content'
);
select extensions.is(
  (select version::integer from public.household_tasks where id = current_setting('tenora_test.shared_task_id')::uuid),
  2,
  'Unauthorized updates do not advance task versions'
);
select extensions.is(
  (select count(*)::integer
     from public.household_tasks
    where title = 'Unauthorized task'),
  0,
  'Rejected writes leave no partial task data'
);

select * from extensions.finish();
rollback;
