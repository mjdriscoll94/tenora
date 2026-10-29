-- Cover household task foreign keys used by retention checks and actor history.
create index household_tasks_created_by_idx
  on public.household_tasks (created_by);

create index household_tasks_updated_by_idx
  on public.household_tasks (updated_by);

create index household_tasks_completed_by_idx
  on public.household_tasks (completed_by)
  where completed_by is not null;

create index household_task_events_task_household_idx
  on public.household_task_events (task_id, household_id);

create index household_task_events_actor_idx
  on public.household_task_events (actor_user_id);
