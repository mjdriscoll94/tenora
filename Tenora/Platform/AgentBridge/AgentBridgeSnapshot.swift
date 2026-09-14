import Foundation

struct AgentBridgeSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let focusedTaskID: UUID?
    let timeZone: String
    let notesIncluded: Bool
    let calendarIncluded: Bool
    let tasks: [AgentBridgeTask]
    let events: [AgentBridgeEvent]
    let workingSchedule: String?

    init(tasks: [TenoraTask], events: [CalendarEvent], focusedTaskID: UUID?, notesIncluded: Bool,
         calendarIncluded: Bool, generatedAt: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        schemaVersion = 1
        self.generatedAt = generatedAt
        self.focusedTaskID = focusedTaskID
        self.timeZone = timeZone.identifier
        self.notesIncluded = notesIncluded
        self.calendarIncluded = calendarIncluded
        self.tasks = tasks.map { AgentBridgeTask($0, includeNotes: notesIncluded) }
        self.events = calendarIncluded ? events.map(AgentBridgeEvent.init) : []
        workingSchedule = UserDefaults.standard.string(forKey: AttentionPreferences.scheduleKey)
    }
}

struct AgentBridgeTask: Codable, Equatable, Sendable {
    let id: UUID; let title: String; let notes: String; let createdAt: Date; let status: TaskStatus
    let dueDate: Date?; let scheduledDate: Date?; let preferredTime: Date?; let estimatedDurationMinutes: Int?
    let priority: TaskPriority; let nextSurfaceAt: Date?; let completedAt: Date?; let tags: [String]
    let nextStep: String?; let heldAt: Date?; let holdReason: String?; let lastWorkedAt: Date?; let returnSummary: String?

    init(_ task: TenoraTask, includeNotes: Bool) {
        id = task.id; title = task.title; notes = includeNotes ? task.notes : ""; createdAt = task.createdAt; status = task.status
        dueDate = task.dueDate; scheduledDate = task.scheduledDate; preferredTime = task.preferredTime
        estimatedDurationMinutes = task.estimatedDurationMinutes; priority = task.priority; nextSurfaceAt = task.nextSurfaceAt
        completedAt = task.completedAt; tags = task.tags; nextStep = task.nextStep; heldAt = task.heldAt
        holdReason = task.holdReason; lastWorkedAt = task.lastWorkedAt; returnSummary = task.returnTrigger?.summary
    }
}

struct AgentBridgeEvent: Codable, Equatable, Sendable {
    let id: String; let title: String; let startDate: Date; let endDate: Date; let isAllDay: Bool; let calendarName: String; let isBusy: Bool
    init(_ event: CalendarEvent) {
        id = event.externalIdentifier; title = event.title; startDate = event.startDate; endDate = event.endDate
        isAllDay = event.isAllDay; calendarName = event.calendarName; isBusy = event.isBusy
    }
}
