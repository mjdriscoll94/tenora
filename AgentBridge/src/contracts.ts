import { z } from "zod";

const optionalDate = z.string().datetime({ offset: true }).nullable().optional();

export const taskSchema = z.object({
  id: z.string().uuid(),
  title: z.string().min(1).max(500),
  notes: z.string().max(20_000).default(""),
  createdAt: z.string().datetime({ offset: true }),
  status: z.enum(["inbox", "active", "scheduled", "waiting", "completed", "archived"]),
  dueDate: optionalDate,
  scheduledDate: optionalDate,
  preferredTime: optionalDate,
  estimatedDurationMinutes: z.number().int().positive().max(1440).nullable().optional(),
  priority: z.enum(["normal", "important", "critical"]),
  nextSurfaceAt: optionalDate,
  completedAt: optionalDate,
  tags: z.array(z.string().max(100)).max(50).default([]),
  nextStep: z.string().max(2000).nullable().optional(),
  heldAt: optionalDate,
  holdReason: z.string().max(2000).nullable().optional(),
  lastWorkedAt: optionalDate,
  returnSummary: z.string().max(2000).nullable().optional()
}).strict();

export const eventSchema = z.object({
  id: z.string().min(1).max(1000),
  title: z.string().min(1).max(1000),
  startDate: z.string().datetime({ offset: true }),
  endDate: z.string().datetime({ offset: true }),
  isAllDay: z.boolean(),
  calendarName: z.string().max(500).default(""),
  isBusy: z.boolean()
}).strict();

export const syncSnapshotSchema = z.object({
  schemaVersion: z.literal(1),
  generatedAt: z.string().datetime({ offset: true }),
  focusedTaskID: z.string().uuid().nullable(),
  timeZone: z.string().min(1).max(200),
  notesIncluded: z.boolean(),
  calendarIncluded: z.boolean(),
  tasks: z.array(taskSchema).max(10_000),
  events: z.array(eventSchema).max(2_000),
  workingSchedule: z.string().max(20_000).nullable()
}).strict();

export type SyncedTask = z.infer<typeof taskSchema>;
export type SyncedEvent = z.infer<typeof eventSchema>;
export type SyncSnapshot = z.infer<typeof syncSnapshotSchema>;

export interface StoredSnapshot {
  generatedAt: string;
  focusedTaskID: string | null;
  timeZone: string;
  notesIncluded: boolean;
  calendarIncluded: boolean;
  workingSchedule: string | null;
  tasks: SyncedTask[];
  events: SyncedEvent[];
}
