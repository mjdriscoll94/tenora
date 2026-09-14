import assert from "node:assert/strict";
import test from "node:test";
import type { StoredSnapshot, SyncSnapshot } from "../src/contracts.js";
import { TenoraReadService, type SnapshotRepository } from "../src/repository.js";

class MemoryRepository implements SnapshotRepository {
  constructor(private value: StoredSnapshot | null) {}
  async replace(_userID: string, snapshot: SyncSnapshot) { this.value = snapshot; }
  async get(_userID: string) { return this.value; }
  async delete(_userID: string) { this.value = null; }
}

const now = "2033-05-18T14:00:00.000Z";
const snapshot: StoredSnapshot = {
  generatedAt: now, focusedTaskID: "00000000-0000-4000-8000-000000000001", timeZone: "UTC", notesIncluded: true,
  calendarIncluded: true, workingSchedule: null,
  tasks: [
    { id: "00000000-0000-4000-8000-000000000001", title: "Draft proposal", notes: "For Atlas", createdAt: now,
      status: "active", priority: "important", tags: ["work"], dueDate: "2033-05-18T16:00:00.000Z" },
    { id: "00000000-0000-4000-8000-000000000002", title: "Buy milk", notes: "", createdAt: now,
      status: "inbox", priority: "normal", tags: ["home"] }
  ],
  events: [{ id: "event", title: "Design review", startDate: "2033-05-18T15:00:00.000Z", endDate: "2033-05-18T15:30:00.000Z",
    isAllDay: false, calendarName: "Work", isBusy: true }]
};

test("search is scoped to the user's snapshot and matches notes and tags", async () => {
  const service = new TenoraReadService(new MemoryRepository(snapshot));
  assert.deepEqual((await service.listTasks("user-a", { query: "atlas" })).map((task) => task.title), ["Draft proposal"]);
  assert.deepEqual((await service.listTasks("user-a", { query: "home" })).map((task) => task.title), ["Buy milk"]);
});

test("now context reports focus, counts, freshness, and next event", async () => {
  const service = new TenoraReadService(new MemoryRepository(snapshot));
  const context = await service.getNowContext("user-a", new Date("2033-05-18T14:30:00.000Z"));
  assert.equal((context.currentTask as { title: string }).title, "Draft proposal");
  assert.equal(context.openTaskCount, 2);
  assert.equal((context.nextEvent as { title: string }).title, "Design review");
});

test("an authenticated account with no phone snapshot gets an honest empty state", async () => {
  const service = new TenoraReadService(new MemoryRepository(null));
  assert.deepEqual(await service.getNowContext("new-user"), { connected: true, synced: false });
  assert.deepEqual(await service.listTasks("new-user"), []);
});
