-- Step 04 permission foundation for household-visible work.
-- Personal Tenora tasks remain local-only and are never copied into this table.

create table public.household_tasks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete restrict,
  title text not null,
  notes text not null default '',
  status text not null default 'inbox',
  priority text not null default 'normal',
  due_at timestamptz,
  scheduled_at timestamptz,
  estimated_duration_minutes integer,
  assigned_to uuid references public.tenora_users(id) on delete restrict,
  created_by uuid not null references public.tenora_users(id) on delete restrict,
  updated_by uuid not null references public.tenora_users(id) on delete restrict,
  completed_by uuid references public.tenora_users(id) on delete restrict,
  completed_at timestamptz,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint household_tasks_id_household_unique unique (id, household_id),
  constraint household_tasks_title_check
    check (char_length(btrim(title)) between 1 and 300),
  constraint household_tasks_notes_check
    check (char_length(notes) <= 20000),
  constraint household_tasks_status_check
    check (status in ('inbox', 'active', 'scheduled', 'waiting', 'completed')),
  constraint household_tasks_priority_check
    check (priority in ('normal', 'important', 'critical')),
  constraint household_tasks_duration_check
    check (estimated_duration_minutes is null or estimated_duration_minutes between 1 and 1440),
  constraint household_tasks_version_check check (version >= 1),
  constraint household_tasks_completion_check check (
    (status = 'completed' and completed_by is not null and completed_at is not null)
    or
    (status <> 'completed' and completed_by is null and completed_at is null)
  )
);

create index household_tasks_household_updated_idx
  on public.household_tasks (household_id, updated_at desc);
create index household_tasks_household_active_idx
  on public.household_tasks (household_id, status, due_at)
  where deleted_at is null;
create index household_tasks_assigned_active_idx
  on public.household_tasks (assigned_to, status, due_at)
  where assigned_to is not null and deleted_at is null;

create table public.household_task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null,
  household_id uuid not null,
  actor_user_id uuid not null references public.tenora_users(id) on delete restrict,
  event_type text not null,
  task_version bigint not null,
  occurred_at timestamptz not null default now(),
  constraint household_task_events_task_fkey
    foreign key (task_id, household_id)
    references public.household_tasks(id, household_id)
    on delete restrict,
  constraint household_task_events_type_check check (
    event_type in (
      'task_created',
      'task_updated',
      'task_assigned',
      'task_completed',
      'task_reopened',
      'task_deleted',
      'task_restored'
    )
  )
);

create index household_task_events_task_timeline_idx
  on public.household_task_events (task_id, occurred_at desc);
create index household_task_events_household_timeline_idx
  on public.household_task_events (household_id, occurred_at desc);

create or replace function private.prepare_household_task_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := private.current_tenora_user_id();
begin
  if current_user_id is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if not private.is_active_household_member(new.household_id) then
      raise exception 'active household membership required' using errcode = '42501';
    end if;

    new.title := btrim(new.title);
    new.created_by := current_user_id;
    new.updated_by := current_user_id;
    new.version := 1;
    new.created_at := now();
    new.updated_at := new.created_at;
    new.deleted_at := null;
  else
    if new.id <> old.id
       or new.household_id <> old.household_id
       or new.created_by <> old.created_by
       or new.created_at <> old.created_at then
      raise exception 'task identity and household cannot change' using errcode = '23514';
    end if;

    if not private.is_active_household_member(old.household_id) then
      raise exception 'active household membership required' using errcode = '42501';
    end if;

    new.title := btrim(new.title);
    new.updated_by := current_user_id;
    new.updated_at := now();
    new.version := old.version + 1;

    if old.deleted_at is null and new.deleted_at is not null then
      new.deleted_at := now();
    elsif old.deleted_at is not null and new.deleted_at is null then
      new.deleted_at := null;
    else
      new.deleted_at := old.deleted_at;
    end if;
  end if;

  if new.assigned_to is not null and not exists (
    select 1
      from public.household_memberships membership
     where membership.household_id = new.household_id
       and membership.user_id = new.assigned_to
       and membership.status = 'active'
  ) then
    raise exception 'assignee must be an active household member' using errcode = '23514';
  end if;

  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    new.completed_by := current_user_id;
    new.completed_at := now();
  elsif new.status <> 'completed' then
    new.completed_by := null;
    new.completed_at := null;
  elsif tg_op = 'UPDATE' then
    new.completed_by := old.completed_by;
    new.completed_at := old.completed_at;
  end if;

  return new;
end;
$$;

create or replace function private.record_household_task_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_name text;
begin
  if tg_op = 'INSERT' then
    event_name := 'task_created';
  elsif old.deleted_at is null and new.deleted_at is not null then
    event_name := 'task_deleted';
  elsif old.deleted_at is not null and new.deleted_at is null then
    event_name := 'task_restored';
  elsif old.status <> 'completed' and new.status = 'completed' then
    event_name := 'task_completed';
  elsif old.status = 'completed' and new.status <> 'completed' then
    event_name := 'task_reopened';
  elsif old.assigned_to is distinct from new.assigned_to then
    event_name := 'task_assigned';
  else
    event_name := 'task_updated';
  end if;

  insert into public.household_task_events (
    task_id,
    household_id,
    actor_user_id,
    event_type,
    task_version
  ) values (
    new.id,
    new.household_id,
    new.updated_by,
    event_name,
    new.version
  );

  return new;
end;
$$;

revoke all on function private.prepare_household_task_write()
  from public, anon, authenticated;
revoke all on function private.record_household_task_event()
  from public, anon, authenticated;

create trigger before_household_task_write
before insert or update on public.household_tasks
for each row execute function private.prepare_household_task_write();

create trigger after_household_task_write
after insert or update on public.household_tasks
for each row execute function private.record_household_task_event();

alter table public.household_tasks enable row level security;
alter table public.household_task_events enable row level security;

create policy "active members can read household tasks"
on public.household_tasks for select to authenticated
using (private.is_active_household_member(household_id));

create policy "active members can create household tasks"
on public.household_tasks for insert to authenticated
with check (
  private.is_active_household_member(household_id)
  and created_by = private.current_tenora_user_id()
  and updated_by = private.current_tenora_user_id()
);

create policy "active members can update household tasks"
on public.household_tasks for update to authenticated
using (private.is_active_household_member(household_id))
with check (
  private.is_active_household_member(household_id)
  and updated_by = private.current_tenora_user_id()
);

create policy "active members can read household task history"
on public.household_task_events for select to authenticated
using (private.is_active_household_member(household_id));

revoke all on table public.household_tasks from public, anon, authenticated;
revoke all on table public.household_task_events from public, anon, authenticated;

grant select on table public.household_tasks to authenticated;
grant insert (
  household_id,
  title,
  notes,
  status,
  priority,
  due_at,
  scheduled_at,
  estimated_duration_minutes,
  assigned_to
) on table public.household_tasks to authenticated;
grant update (
  title,
  notes,
  status,
  priority,
  due_at,
  scheduled_at,
  estimated_duration_minutes,
  assigned_to,
  deleted_at
) on table public.household_tasks to authenticated;
grant select on table public.household_task_events to authenticated;

comment on table public.household_tasks is
  'Explicitly household-visible tasks. Personal Tenora tasks remain local-only and separate.';
comment on table public.household_task_events is
  'Immutable actor and version history for household task changes.';

