do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'tenora_bridge') then
    create role tenora_bridge
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls;
  end if;
end
$$;

create table if not exists tenora_snapshots (
  user_id text primary key,
  generated_at timestamptz not null,
  received_at timestamptz not null default now(),
  focused_task_id uuid,
  time_zone text not null default 'UTC',
  notes_included boolean not null default false,
  calendar_included boolean not null default false,
  working_schedule text,
  payload jsonb not null default '{"tasks":[],"events":[]}'::jsonb,
  constraint payload_is_object check (jsonb_typeof(payload) = 'object')
);

alter table tenora_snapshots enable row level security;
alter table tenora_snapshots force row level security;

drop policy if exists tenora_snapshot_owner on tenora_snapshots;
create policy tenora_snapshot_owner on tenora_snapshots
  using (user_id = current_setting('app.user_id', true))
  with check (user_id = current_setting('app.user_id', true));

revoke all on tenora_snapshots from public;
grant usage on schema public to tenora_bridge;
grant select, insert, update, delete on tenora_snapshots to tenora_bridge;
