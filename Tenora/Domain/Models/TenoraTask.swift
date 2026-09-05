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
        tags: [String] = []
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
    }

    mutating func complete(at date: Date = Date()) {
        status = .completed
        completedAt = date
        nextSurfaceAt = nil
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
