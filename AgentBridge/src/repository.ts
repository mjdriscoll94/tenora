import type { StoredSnapshot, SyncSnapshot, SyncedTask } from "./contracts.js";

export interface SnapshotRepository {
  replace(userID: string, snapshot: SyncSnapshot): Promise<void>;
  get(userID: string): Promise<StoredSnapshot | null>;
  delete(userID: string): Promise<void>;
}

export interface TaskFilter {
  status?: SyncedTask["status"];
  query?: string;
  limit?: number;
}

export class TenoraReadService {
  constructor(private readonly repository: SnapshotRepository) {}

  async listTasks(userID: string, filter: TaskFilter = {}): Promise<SyncedTask[]> {
    const snapshot = await this.repository.get(userID);
    if (!snapshot) return [];
    const query = filter.query?.trim().toLocaleLowerCase();
    return snapshot.tasks
      .filter((task) => !filter.status || task.status === filter.status)
      .filter((task) => !query || `${task.title}\n${task.notes}\n${task.nextStep ?? ""}\n${task.tags.join(" ")}`.toLocaleLowerCase().includes(query))
      .sort((a, b) => this.taskSortKey(a) - this.taskSortKey(b))
      .slice(0, Math.min(filter.limit ?? 100, 200));
  }

  async getTask(userID: string, id: string): Promise<SyncedTask | null> {
    const snapshot = await this.repository.get(userID);
    return snapshot?.tasks.find((task) => task.id === id) ?? null;
  }

  async getNowContext(userID: string, now = new Date()): Promise<Record<string, unknown>> {
    const snapshot = await this.repository.get(userID);
    if (!snapshot) return { connected: true, synced: false };
    const current = snapshot.tasks.find((task) => task.id === snapshot.focusedTaskID) ?? null;
    const open = snapshot.tasks.filter((task) => !["completed", "archived"].includes(task.status));
    const overdue = open.filter((task) => task.dueDate && new Date(task.dueDate) < now);
    const nextEvent = snapshot.events
      .filter((event) => new Date(event.endDate) > now)
      .sort((a, b) => Date.parse(a.startDate) - Date.parse(b.startDate))[0] ?? null;
    return {
      connected: true,
      synced: true,
      snapshotGeneratedAt: snapshot.generatedAt,
      timeZone: snapshot.timeZone,
      notesIncluded: snapshot.notesIncluded,
      currentTask: current,
      openTaskCount: open.length,
      overdueTaskCount: overdue.length,
      calendarIncluded: snapshot.calendarIncluded,
      nextEvent
    };
  }

  async getTodaySchedule(userID: string, now = new Date()): Promise<Record<string, unknown>> {
    const snapshot = await this.repository.get(userID);
    if (!snapshot) return { synced: false, events: [], scheduledTasks: [] };
    const formatter = new Intl.DateTimeFormat("en-CA", { timeZone: snapshot.timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
    const localDay = formatter.format(now);
    return {
      synced: true,
      calendarIncluded: snapshot.calendarIncluded,
      notesIncluded: snapshot.notesIncluded,
      events: snapshot.events.filter((event) => formatter.format(new Date(event.startDate)) === localDay),
      scheduledTasks: snapshot.tasks.filter((task) => task.scheduledDate && formatter.format(new Date(task.scheduledDate)) === localDay),
      workingSchedule: snapshot.workingSchedule
    };
  }

  private taskSortKey(task: SyncedTask): number {
    return Date.parse(task.dueDate ?? task.scheduledDate ?? task.nextSurfaceAt ?? task.createdAt);
  }
}
