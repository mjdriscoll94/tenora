import Foundation

struct TaskPriorityEngine: Sendable {
    struct Context: Sendable {
        let now: Date
        let availableMinutes: Int?
        let calendar: Calendar

        init(now: Date, availableMinutes: Int? = nil, calendar: Calendar = .current) {
            self.now = now
            self.availableMinutes = availableMinutes
            self.calendar = calendar
        }
    }

    func recommendation(
        from tasks: [TenoraTask],
        context: Context
    ) -> TenoraTask? {
        tasks
            .filter { isEligible($0, context: context) }
            .max { lhs, rhs in
                let lhsScore = score(for: lhs, context: context)
                let rhsScore = score(for: rhs, context: context)
                if lhsScore == rhsScore {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhsScore < rhsScore
            }
    }

    func score(for task: TenoraTask, context: Context) -> Int {
        priorityWeight(task.priority)
            + dueDateWeight(task.dueDate, context: context)
            + schedulingWeight(task.scheduledDate, context: context)
            + resurfacingWeight(task, now: context.now)
            + availabilityWeight(task.estimatedDurationMinutes, available: context.availableMinutes)
    }

    private func isEligible(_ task: TenoraTask, context: Context) -> Bool {
        guard [.inbox, .active, .scheduled].contains(task.status) else { return false }

        if let scheduledDate = task.scheduledDate,
           scheduledDate > context.calendar.endOfDay(containing: context.now),
           task.dueDate == nil {
            return false
        }
        return true
    }

    private func priorityWeight(_ priority: TaskPriority) -> Int {
        switch priority {
        case .normal: 0
        case .important: 30
        case .critical: 60
        }
    }

    private func dueDateWeight(_ dueDate: Date?, context: Context) -> Int {
        guard let dueDate else { return 0 }
        let calendar = context.calendar
        let startOfToday = calendar.startOfDay(for: context.now)
        let dueDay = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: startOfToday, to: dueDay).day ?? 0

        switch days {
        case ..<0: return 100
        case 0: return 80
        case 1...3: return 50
        case 4...7: return 25
        default: return 0
        }
    }

    private func schedulingWeight(_ scheduledDate: Date?, context: Context) -> Int {
        guard let scheduledDate else { return 0 }
        return context.calendar.isDate(scheduledDate, inSameDayAs: context.now) ? 60 : 0
    }

    private func resurfacingWeight(_ task: TenoraTask, now: Date) -> Int {
        var weight = min(task.snoozeCount * 8, 32)
        if let nextSurfaceAt = task.nextSurfaceAt, nextSurfaceAt <= now {
            weight += 40
        }
        if let lastSurfacedAt = task.lastSurfacedAt {
            let daysSinceSurface = max(0, Int(now.timeIntervalSince(lastSurfacedAt) / 86_400))
            weight += min(daysSinceSurface * 5, 20)
        } else {
            let daysSinceCreation = max(0, Int(now.timeIntervalSince(task.createdAt) / 86_400))
            weight += min(daysSinceCreation * 5, 20)
        }
        return weight
    }

    private func availabilityWeight(_ duration: Int?, available: Int?) -> Int {
        guard let duration, let available else { return 0 }
        return duration <= available ? 15 : -25
    }
}

private extension Calendar {
    func endOfDay(containing date: Date) -> Date {
        let startOfTomorrow = self.date(byAdding: .day, value: 1, to: startOfDay(for: date)) ?? date
        return startOfTomorrow.addingTimeInterval(-1)
    }
}
