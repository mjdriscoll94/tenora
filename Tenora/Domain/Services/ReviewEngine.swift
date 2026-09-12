import Foundation

enum ReviewKind: String, Identifiable { case morning, evening; var id: String { rawValue } }
enum ReviewDecision { case today, tomorrow, keep, complete, schedule(Date) }

struct ReviewEngine {
    func queue(tasks: [TenoraTask], now: Date, calendar: Calendar = .current) -> [TenoraTask] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return tasks.filter {
            [.inbox, .active, .scheduled].contains($0.status) && ($0.scheduledDate ?? now) < tomorrow
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func apply(_ decision: ReviewDecision, to task: TenoraTask, now: Date, calendar: Calendar = .current) -> TenoraTask {
        guard ![.completed, .archived].contains(task.status) else { return task }
        var result = task
        result.clearJustStart()
        switch decision {
        case .complete: result.complete(at: now)
        case .today:
            result.status = .active
            result.scheduledDate = now
            result.nextSurfaceAt = now
            result.snoozeCount = 0
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            result.status = .scheduled
            result.scheduledDate = date
            result.nextSurfaceAt = date
            result.snoozeCount = 0
        case .keep:
            result = ResurfacingEngine().postpone(result, at: now, calendar: calendar)
        case .schedule(let date):
            result.status = .scheduled
            result.scheduledDate = date
            result.nextSurfaceAt = date
            result.snoozeCount = 0
        }
        return result
    }
}
