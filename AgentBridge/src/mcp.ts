import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import type { Request, Response } from "express";
import { z } from "zod";
import type { SyncedTask } from "./contracts.js";
import { TenoraReadService } from "./repository.js";

const taskOutput = z.object({
  id: z.string(), title: z.string(), notes: z.string(), createdAt: z.string(), status: z.string(),
  dueDate: z.string().nullable().optional(), scheduledDate: z.string().nullable().optional(),
  preferredTime: z.string().nullable().optional(), estimatedDurationMinutes: z.number().nullable().optional(),
  priority: z.string(), nextSurfaceAt: z.string().nullable().optional(), completedAt: z.string().nullable().optional(),
  tags: z.array(z.string()), nextStep: z.string().nullable().optional(), heldAt: z.string().nullable().optional(),
  holdReason: z.string().nullable().optional(), lastWorkedAt: z.string().nullable().optional(),
  returnSummary: z.string().nullable().optional()
});

const readOnly = { readOnlyHint: true, openWorldHint: false, destructiveHint: false } as const;

export function createTenoraMcpServer(userID: string, service: TenoraReadService, appURL: string): McpServer {
  const server = new McpServer(
    { name: "tenora", version: "0.1.0" },
    { instructions: "Use Tenora tools only for the authenticated user's tasks and schedule. This version is read-only. Never imply that a task was changed." }
  );

  server.registerTool("list_tasks", {
    title: "List Tenora tasks",
    description: "List or filter the user's synchronized Tenora tasks. Use for workload, status, deadline, and planning questions.",
    inputSchema: {
      status: z.enum(["inbox", "active", "scheduled", "waiting", "completed", "archived"]).optional(),
      query: z.string().max(500).optional(),
      limit: z.number().int().min(1).max(200).default(100)
    },
    outputSchema: { tasks: z.array(taskOutput) }, annotations: readOnly
  }, async ({ status, query, limit }) => {
    const tasks = await service.listTasks(userID, { status, query, limit });
    return toolResult({ tasks }, `Found ${tasks.length} Tenora task${tasks.length === 1 ? "" : "s"}.`);
  });

  server.registerTool("get_task", {
    title: "Get a Tenora task",
    description: "Get one synchronized Tenora task by its stable UUID.",
    inputSchema: { id: z.string().uuid() },
    outputSchema: { task: taskOutput.nullable() }, annotations: readOnly
  }, async ({ id }) => {
    const task = await service.getTask(userID, id);
    return toolResult({ task }, task ? `Found ${task.title}.` : "That task is not in the synchronized Tenora snapshot.");
  });

  server.registerTool("get_now_context", {
    title: "Get Tenora now context",
    description: "Get the user's current task, next event, open-task count, overdue count, and snapshot freshness.",
    inputSchema: {}, annotations: readOnly
  }, async () => {
    const context = await service.getNowContext(userID);
    return toolResult(context, context.synced === false ? "Tenora is connected but the phone has not synced yet." : "Loaded the current Tenora context.");
  });

  server.registerTool("get_today_schedule", {
    title: "Get today's Tenora schedule",
    description: "Get calendar events and scheduled tasks included in the latest opt-in Tenora snapshot.",
    inputSchema: {}, annotations: readOnly
  }, async () => {
    const schedule = await service.getTodaySchedule(userID);
    return toolResult(schedule, schedule.calendarIncluded === false ? "Calendar sharing is off; returning tasks only." : "Loaded today's Tenora schedule.");
  });

  server.registerTool("search", {
    title: "Search Tenora",
    description: "Search task titles, notes, next steps, and tags in the user's synchronized Tenora data.",
    inputSchema: { query: z.string().min(1).max(500) }, annotations: readOnly
  }, async ({ query }) => {
    const tasks = await service.listTasks(userID, { query, limit: 50 });
    const results = tasks.map((task) => ({ id: task.id, title: task.title, url: `${appURL.replace(/\/$/, "")}/tasks/${task.id}` }));
    return toolResult({ results }, `Found ${results.length} matching Tenora task${results.length === 1 ? "" : "s"}.`);
  });

  server.registerTool("fetch", {
    title: "Fetch a Tenora search result",
    description: "Fetch the complete task represented by a Tenora search-result ID.",
    inputSchema: { id: z.string().uuid() }, annotations: readOnly
  }, async ({ id }) => {
    const task = await service.getTask(userID, id);
    if (!task) return toolResult({ id, found: false }, "That task is no longer present.");
    return toolResult({ id, found: true, title: task.title, text: taskText(task), url: `${appURL.replace(/\/$/, "")}/tasks/${task.id}` }, `Fetched ${task.title}.`);
  });
  return server;
}

export async function handleMcpRequest(request: Request, response: Response, server: McpServer): Promise<void> {
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  response.on("close", () => { void transport.close(); void server.close(); });
  await server.connect(transport);
  await transport.handleRequest(request, response, request.body);
}

function toolResult<T extends Record<string, unknown>>(structuredContent: T, text: string) {
  return { structuredContent, content: [{ type: "text" as const, text }] };
}

function taskText(task: SyncedTask): string {
  return [task.title, task.notes, task.nextStep ? `Next step: ${task.nextStep}` : "", task.dueDate ? `Due: ${task.dueDate}` : "",
    `Status: ${task.status}`, `Priority: ${task.priority}`, task.tags.length ? `Tags: ${task.tags.join(", ")}` : ""].filter(Boolean).join("\n");
}
