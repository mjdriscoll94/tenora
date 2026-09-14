import pg from "pg";
import type { SnapshotRepository } from "./repository.js";
import type { StoredSnapshot, SyncSnapshot } from "./contracts.js";

export class PostgresSnapshotRepository implements SnapshotRepository {
  private readonly pool: pg.Pool;

  constructor(connectionString: string) {
    this.pool = new pg.Pool({ connectionString, max: 10, idleTimeoutMillis: 30_000 });
  }

  async replace(userID: string, snapshot: SyncSnapshot): Promise<void> {
    await this.withUser(userID, async (client) => {
      await client.query(
        `insert into tenora_snapshots (user_id, generated_at, focused_task_id, time_zone, notes_included, calendar_included, working_schedule, payload)
         values ($1, $2, $3, $4, $5, $6, $7, $8)
         on conflict (user_id) do update set generated_at = excluded.generated_at,
           focused_task_id = excluded.focused_task_id, time_zone = excluded.time_zone,
           notes_included = excluded.notes_included, calendar_included = excluded.calendar_included,
           working_schedule = excluded.working_schedule, payload = excluded.payload, received_at = now()
         where tenora_snapshots.generated_at <= excluded.generated_at`,
        [userID, snapshot.generatedAt, snapshot.focusedTaskID, snapshot.timeZone, snapshot.notesIncluded,
         snapshot.calendarIncluded, snapshot.workingSchedule, JSON.stringify({ tasks: snapshot.tasks, events: snapshot.events })]
      );
    });
  }

  async get(userID: string): Promise<StoredSnapshot | null> {
    return this.withUser(userID, async (client) => {
      const result = await client.query<{
        generated_at: Date; focused_task_id: string | null; time_zone: string; notes_included: boolean; calendar_included: boolean;
        working_schedule: string | null; payload: { tasks: StoredSnapshot["tasks"]; events: StoredSnapshot["events"] };
      }>(`select generated_at, focused_task_id, time_zone, notes_included, calendar_included, working_schedule, payload
          from tenora_snapshots where user_id = $1`, [userID]);
      const row = result.rows[0];
      if (!row) return null;
      return {
        generatedAt: row.generated_at.toISOString(),
        focusedTaskID: row.focused_task_id,
        timeZone: row.time_zone,
        notesIncluded: row.notes_included,
        calendarIncluded: row.calendar_included,
        workingSchedule: row.working_schedule,
        tasks: row.payload.tasks,
        events: row.payload.events
      };
    });
  }

  async delete(userID: string): Promise<void> {
    await this.withUser(userID, async (client) => { await client.query("delete from tenora_snapshots where user_id = $1", [userID]); });
  }

  async close(): Promise<void> { await this.pool.end(); }

  private async withUser<T>(userID: string, operation: (client: pg.PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      await client.query("select set_config('app.user_id', $1, true)", [userID]);
      const result = await operation(client);
      await client.query("commit");
      return result;
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally { client.release(); }
  }
}
