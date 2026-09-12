import Foundation
import SwiftData

@Model
final class StoredTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var createdAt: Date
    var statusValue: String
    var dueDate: Date?
    var scheduledDate: Date?
    var preferredTime: Date?
    var estimatedDurationMinutes: Int?
    var priorityValue: String
    var lastSurfacedAt: Date?
    var nextSurfaceAt: Date?
    var surfaceCount: Int
    var snoozeCount: Int
    var completedAt: Date?
    var sourceValue: String
    var tags: [String]
    var nextStep: String?
    var heldAt: Date?
    var holdReason: String?
    var lastWorkedAt: Date?
    var justStartBeganAt: Date?
    var justStartDurationSeconds: Int?

    init(task: TenoraTask) {
        id = task.id
        title = task.title
        notes = task.notes
        createdAt = task.createdAt
        statusValue = task.status.rawValue
        dueDate = task.dueDate
        scheduledDate = task.scheduledDate
        preferredTime = task.preferredTime
        estimatedDurationMinutes = task.estimatedDurationMinutes
        priorityValue = task.priority.rawValue
        lastSurfacedAt = task.lastSurfacedAt
        nextSurfaceAt = task.nextSurfaceAt
        surfaceCount = task.surfaceCount
        snoozeCount = task.snoozeCount
        completedAt = task.completedAt
        sourceValue = task.source.rawValue
        tags = task.tags
        nextStep = task.nextStep
        heldAt = task.heldAt
        holdReason = task.holdReason
        lastWorkedAt = task.lastWorkedAt
        justStartBeganAt = task.justStartBeganAt
        justStartDurationSeconds = task.justStartDurationSeconds
    }

    func update(from task: TenoraTask) {
        title = task.title
        notes = task.notes
        statusValue = task.status.rawValue
        dueDate = task.dueDate
        scheduledDate = task.scheduledDate
        preferredTime = task.preferredTime
        estimatedDurationMinutes = task.estimatedDurationMinutes
        priorityValue = task.priority.rawValue
        lastSurfacedAt = task.lastSurfacedAt
        nextSurfaceAt = task.nextSurfaceAt
        surfaceCount = task.surfaceCount
        snoozeCount = task.snoozeCount
        completedAt = task.completedAt
        sourceValue = task.source.rawValue
        tags = task.tags
        nextStep = task.nextStep
        heldAt = task.heldAt
        holdReason = task.holdReason
        lastWorkedAt = task.lastWorkedAt
        justStartBeganAt = task.justStartBeganAt
        justStartDurationSeconds = task.justStartDurationSeconds
    }

    var domainModel: TenoraTask {
        TenoraTask(
            id: id,
            title: title,
            notes: notes,
            createdAt: createdAt,
            status: TaskStatus(rawValue: statusValue) ?? .inbox,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            preferredTime: preferredTime,
            estimatedDurationMinutes: estimatedDurationMinutes,
            priority: TaskPriority(rawValue: priorityValue) ?? .normal,
            lastSurfacedAt: lastSurfacedAt,
            nextSurfaceAt: nextSurfaceAt,
            surfaceCount: surfaceCount,
            snoozeCount: snoozeCount,
            completedAt: completedAt,
            source: TaskSource(rawValue: sourceValue) ?? .manual,
            tags: tags,
            nextStep: nextStep,
            heldAt: heldAt,
            holdReason: holdReason,
            lastWorkedAt: lastWorkedAt,
            justStartBeganAt: justStartBeganAt,
            justStartDurationSeconds: justStartDurationSeconds
        )
    }
}
