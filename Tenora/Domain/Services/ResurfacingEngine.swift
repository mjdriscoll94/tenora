import Foundation

struct ResurfacingEngine: Sendable {
    func initialSurfaceDate(
        for task: TenoraTask,
        calendar: Calendar = .current
    ) -> Date? {
        guard task.dueDate == nil, task.scheduledDate == nil else { return nil }

        let candidate = task.createdAt.addingTimeInterval(4 * 60 * 60)
        let evening = time(onDayContaining: task.createdAt, hour: 20, calendar: calendar)
        if candidate < evening {
            return candidate
        }
        return nextMorning(after: task.createdAt, calendar: calendar)
    }

    func tasksToSurface(
        from tasks: [TenoraTask],
        at date: Date
    ) -> [TenoraTask] {
        tasks
            .filter { task in
                guard [.inbox, .active, .scheduled].contains(task.status),
                      let nextSurfaceAt = task.nextSurfaceAt else { return false }
                if let scheduled = task.scheduledDate, scheduled > date { return false }
                return nextSurfaceAt <= date
            }
            .sorted {
                ($0.nextSurfaceAt ?? .distantFuture) < ($1.nextSurfaceAt ?? .distantFuture)
            }
    }

    func postpone(
        _ task: TenoraTask,
        at date: Date,
        calendar: Calendar = .current
    ) -> TenoraTask {
        var updated = task
        updated.lastSurfacedAt = date
        updated.surfaceCount += 1
        updated.snoozeCount += 1

        switch updated.snoozeCount {
        case 1:
            updated.nextSurfaceAt = date.addingTimeInterval(3 * 60 * 60)
        case 2:
            let evening = time(onDayContaining: date, hour: 19, calendar: calendar)
            updated.nextSurfaceAt = evening > date
                ? evening
                : nextMorning(after: date, calendar: calendar)
        case 3:
            let eveningReview = time(onDayContaining: date, hour: 20, calendar: calendar)
            updated.nextSurfaceAt = eveningReview > date
                ? eveningReview
                : nextMorning(after: date, calendar: calendar)
        default:
            updated.nextSurfaceAt = nextMorning(after: date, calendar: calendar)
        }
        return updated
    }

    private func time(onDayContaining date: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    private func nextMorning(after date: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
