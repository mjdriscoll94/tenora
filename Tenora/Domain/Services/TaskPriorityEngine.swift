import Foundation

struct TaskPriorityEngine: Sendable {
    struct Context: Sendable {
        let now: Date
        let availableMinutes: Int?
        let calendar: Calendar
        let workingHours: WorkingHours
        let schedule: WorkingSchedule?

        init(now: Date, availableMinutes: Int? = nil, calendar: Calendar = .current, workingHours: WorkingHours = WorkingHours(), schedule: WorkingSchedule? = nil) {
            self.now = now
            self.availableMinutes = availableMinutes
            self.calendar = calendar
            self.workingHours = workingHours
            self.schedule = schedule
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

    func isEligible(_ task: TenoraTask, context: Context) -> Bool {
        guard [.inbox, .active, .scheduled].contains(task.status) else { return false }
        let hour = context.calendar.component(.hour, from: context.now)
        let working = context.schedule?.isWorking(at: context.now, calendar: context.calendar) ?? (hour >= context.workingHours.startHour && hour < context.workingHours.endHour)
        guard working,
              context.availableMinutes != 0 else { return false }
        if let scheduled = task.scheduledDate, scheduled > context.now { return false }
        if task.snoozeCount > 0, let next = task.nextSurfaceAt, next > context.now { return false }
        if let duration = task.estimatedDurationMinutes, let available = context.availableMinutes, duration > available { return false }
        return true
    }

    func reason(for task: TenoraTask, context: Context) -> String {
        if let due = task.dueDate, due <= context.now { return "Its deadline has passed. Choose a next step when you're ready." }
        if let due = task.dueDate, context.calendar.isDate(due, inSameDayAs: context.now) { return "This is due today." }
        if let duration = task.estimatedDurationMinutes, let available = context.availableMinutes, duration <= available {
            return "Its estimate fits the time in your calendar."
        }
        if let scheduled = task.scheduledDate, scheduled <= context.now { return "You made room for this today." }
        if task.snoozeCount >= 3 { return "Still important? You can schedule it or let it go." }
        if task.nextSurfaceAt.map({ $0 <= context.now }) == true { return "It's ready for another look." }
        if task.priority != .normal { return "You marked this as \(task.priority.rawValue)." }
        return "One small next step from the things you're holding."
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
