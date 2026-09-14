import assert from "node:assert/strict";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { StoredSnapshot, SyncSnapshot } from "../src/contracts.js";
import { createTenoraMcpServer } from "../src/mcp.js";
import { TenoraReadService, type SnapshotRepository } from "../src/repository.js";

class OneUserRepository implements SnapshotRepository {
  constructor(private snapshot: StoredSnapshot) {}
  async replace(_userID: string, value: SyncSnapshot) { this.snapshot = value; }
  async get(userID: string) { return userID === "user-a" ? this.snapshot : null; }
  async delete(_userID: string) {}
}

test("MCP advertises only read-only tools and returns structured task data", async () => {
  const snapshot: StoredSnapshot = {
    generatedAt: "2033-05-18T14:00:00.000Z", focusedTaskID: null, timeZone: "UTC", notesIncluded: false,
    calendarIncluded: false, workingSchedule: null, events: [],
    tasks: [{ id: "00000000-0000-4000-8000-000000000001", title: "Plan launch", notes: "",
      createdAt: "2033-05-18T14:00:00.000Z", status: "inbox", priority: "important", tags: ["work"] }]
  };
  const server = createTenoraMcpServer("user-a", new TenoraReadService(new OneUserRepository(snapshot)), "https://tenora.example");
  const client = new Client({ name: "tenora-test", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  const tools = await client.listTools();
  assert.deepEqual(tools.tools.map((tool) => tool.name).sort(), ["fetch", "get_now_context", "get_task", "get_today_schedule", "list_tasks", "search"]);
  assert.ok(tools.tools.every((tool) => tool.annotations?.readOnlyHint === true && tool.annotations?.destructiveHint === false));
  const result = await client.callTool({ name: "list_tasks", arguments: { status: "inbox" } });
  assert.equal((result.structuredContent as { tasks: Array<{ title: string }> }).tasks[0]?.title, "Plan launch");
  await client.close();
  await server.close();
});
