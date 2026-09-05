import Foundation

struct PlannedReminder: Equatable {
    let taskID: UUID
    let title: String
    let date: Date
}

struct ReminderPlanner {
    // Reserve headroom under iOS's pending-notification limit. No more than
    // three reminders per local day; unresolved work returns over seven days.
    func plan(tasks: [TenoraTask], now: Date, calendar: Calendar = .current, usedSlots: [Date] = []) -> [PlannedReminder] {
        var candidates: [PlannedReminder] = []
        let horizon = calendar.date(byAdding: .day, value: 7, to: now)!
        for task in tasks where [.inbox, .active, .scheduled].contains(task.status) {
            var date = max(task.nextSurfaceAt ?? task.scheduledDate ?? task.dueDate ?? task.createdAt.addingTimeInterval(4 * 3600), now.addingTimeInterval(60))
            if let scheduled = task.scheduledDate { date = max(date, scheduled) }
            for _ in 0..<7 {
                date = allowedTime(date, calendar: calendar)
                guard date < horizon else { break }
                candidates.append(.init(taskID: task.id, title: task.title, date: date))
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
        var dailyCounts = Dictionary(grouping: usedSlots, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        var result: [PlannedReminder] = []
        var last: Date? = usedSlots.max()
        for candidate in candidates.sorted(by: { $0.date == $1.date ? $0.taskID.uuidString < $1.taskID.uuidString : $0.date < $1.date }) {
            let spaced = max(candidate.date, last?.addingTimeInterval(2 * 3600) ?? candidate.date)
            let date = allowedTime(spaced, calendar: calendar)
            let day = calendar.startOfDay(for: date)
            guard date < horizon, dailyCounts[day, default: 0] < 3 else { continue }
            result.append(.init(taskID: candidate.taskID, title: candidate.title, date: date))
            dailyCounts[day, default: 0] += 1
            last = date
            if result.count == 21 { break }
        }
        return result
    }

    private func allowedTime(_ date: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: date)
        if hour < 9 { return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)! }
        if hour >= 20 {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        }
        return date
    }
}
