import Foundation

struct TenoraTask: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var title: String
    var notes: String
    let createdAt: Date
    var status: TaskStatus
    var dueDate: Date?
    var scheduledDate: Date?
    var preferredTime: Date?
    var estimatedDurationMinutes: Int?
    var priority: TaskPriority
    var lastSurfacedAt: Date?
    var nextSurfaceAt: Date?
    var surfaceCount: Int
    var snoozeCount: Int
    var completedAt: Date?
    var source: TaskSource
    var tags: [String]
    var nextStep: String?
    var heldAt: Date?
    var holdReason: String?
    var lastWorkedAt: Date?
    var justStartBeganAt: Date?
    var justStartDurationSeconds: Int?
    var returnTrigger: ReturnTrigger?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        status: TaskStatus = .inbox,
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        preferredTime: Date? = nil,
        estimatedDurationMinutes: Int? = nil,
        priority: TaskPriority = .normal,
        lastSurfacedAt: Date? = nil,
        nextSurfaceAt: Date? = nil,
        surfaceCount: Int = 0,
        snoozeCount: Int = 0,
        completedAt: Date? = nil,
        source: TaskSource = .manual,
        tags: [String] = [],
        nextStep: String? = nil,
        heldAt: Date? = nil,
        holdReason: String? = nil,
        lastWorkedAt: Date? = nil,
        justStartBeganAt: Date? = nil,
        justStartDurationSeconds: Int? = nil,
        returnTrigger: ReturnTrigger? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.status = status
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.preferredTime = preferredTime
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.priority = priority
        self.lastSurfacedAt = lastSurfacedAt
        self.nextSurfaceAt = nextSurfaceAt
        self.surfaceCount = surfaceCount
        self.snoozeCount = snoozeCount
        self.completedAt = completedAt
        self.source = source
        self.tags = tags
        self.nextStep = nextStep
        self.heldAt = heldAt
        self.holdReason = holdReason
        self.lastWorkedAt = lastWorkedAt
        self.justStartBeganAt = justStartBeganAt
        self.justStartDurationSeconds = justStartDurationSeconds
        self.returnTrigger = returnTrigger
    }

    var justStartEndsAt: Date? {
        guard let began = justStartBeganAt, let seconds = justStartDurationSeconds, seconds > 0 else { return nil }
        return began.addingTimeInterval(TimeInterval(seconds))
    }

    mutating func clearJustStart() {
        justStartBeganAt = nil
        justStartDurationSeconds = nil
    }

    mutating func complete(at date: Date = Date()) {
        status = .completed
        completedAt = date
        nextSurfaceAt = nil
        returnTrigger = nil
        clearJustStart()
    }
}

enum ReturnTrigger: Equatable, Sendable, Codable {
    case taskCompleted(taskID: UUID, title: String)
    case calendarEventEnded(eventID: String, title: String, endDate: Date)
    case freeWindow(minimumMinutes: Int, candidateDate: Date?)

    var summary: String {
        switch self {
        case .taskCompleted(_, let title): "After \(title) is done"
        case .calendarEventEnded(_, let title, _): "After \(title) ends"
        case .freeWindow(let minutes, _): "When at least \(minutes) minutes opens up"
        }
    }
}

enum TaskStatus: String, CaseIterable, Codable, Sendable {
    case inbox
    case active
    case scheduled
    case waiting
    case completed
    case archived
}

enum TaskPriority: String, CaseIterable, Codable, Sendable {
    case normal
    case important
    case critical
}

enum TaskSource: String, CaseIterable, Codable, Sendable {
    case manual
    case shortcut
    case shareExtension
}
