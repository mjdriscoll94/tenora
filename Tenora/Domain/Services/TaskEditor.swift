import Foundation

enum TaskEditor {
    enum ValidationError: LocalizedError {
        case emptyTitle
        var errorDescription: String? { "Give this task a title before saving." }
    }

    static func validated(_ draft: TenoraTask, previous: TenoraTask, now: Date) throws -> TenoraTask {
        var task = draft
        task.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { throw ValidationError.emptyTitle }
        if task.status != .completed && task.status != .archived {
            task.status = task.scheduledDate == nil ? .inbox : .scheduled
            if task.scheduledDate != previous.scheduledDate || task.dueDate != previous.dueDate {
                task.nextSurfaceAt = task.scheduledDate ?? task.dueDate ?? now.addingTimeInterval(4 * 3600)
                task.snoozeCount = 0
            }
            if draft.nextSurfaceAt != previous.nextSurfaceAt {
                task.nextSurfaceAt = draft.nextSurfaceAt
                task.snoozeCount = (draft.nextSurfaceAt ?? .distantPast) > now ? max(1, previous.snoozeCount) : 0
            }
        }
        return task
    }
}
