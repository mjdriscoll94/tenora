import Foundation

enum TaskCapacityMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case balanced
    case easyWin
    case interesting
    case important
    case mindless
    case quick
    case momentum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Tenora decides"
        case .easyWin: "An easy win"
        case .interesting: "Something interesting"
        case .important: "Something important"
        case .mindless: "Something mindless"
        case .quick: "Something quick"
        case .momentum: "I have momentum"
        }
    }

    var shortTitle: String {
        switch self {
        case .balanced: "Choose my next task"
        case .easyWin: "Easy win"
        case .interesting: "Interesting"
        case .important: "Important"
        case .mindless: "Mindless"
        case .quick: "Quick"
        case .momentum: "Momentum"
        }
    }

    var icon: String {
        switch self {
        case .balanced: "wand.and.stars"
        case .easyWin: "checkmark.circle"
        case .interesting: "sparkles"
        case .important: "exclamationmark.circle"
        case .mindless: "leaf"
        case .quick: "hare"
        case .momentum: "bolt"
        }
    }
}

enum TaskCapacityTrait: String, CaseIterable, Identifiable {
    case easyWin
    case interesting
    case mindless

    private static let tagPrefix = "tenora.capacity."
    var id: String { rawValue }
    var tag: String { Self.tagPrefix + rawValue }

    var title: String {
        switch self {
        case .easyWin: "Feels like an easy win"
        case .interesting: "Usually feels interesting"
        case .mindless: "Can be done without much thinking"
        }
    }
}

extension TenoraTask {
    func hasCapacityTrait(_ trait: TaskCapacityTrait) -> Bool {
        tags.contains(trait.tag)
    }

    mutating func setCapacityTrait(_ trait: TaskCapacityTrait, enabled: Bool) {
        tags.removeAll { $0 == trait.tag }
        if enabled { tags.append(trait.tag) }
    }
}

struct TaskPriorityEngine: Sendable {
    struct Context: Sendable {
        let now: Date
        let availableMinutes: Int?
        let calendar: Calendar
        let workingHours: WorkingHours
        let schedule: WorkingSchedule?
        let capacityMode: TaskCapacityMode

        init(now: Date, availableMinutes: Int? = nil, calendar: Calendar = .current, workingHours: WorkingHours = WorkingHours(), schedule: WorkingSchedule? = nil, capacityMode: TaskCapacityMode = .balanced) {
            self.now = now
            self.availableMinutes = availableMinutes
            self.calendar = calendar
            self.workingHours = workingHours
            self.schedule = schedule
            self.capacityMode = capacityMode
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
            + keepInFrontWeight(task, context: context)
            + capacityWeight(task, context: context)
    }

    func isEligible(_ task: TenoraTask, context: Context) -> Bool {
        guard [.inbox, .active, .scheduled].contains(task.status) else { return false }
        let hour = context.calendar.component(.hour, from: context.now)
        let working = context.schedule?.isWorking(at: context.now, calendar: context.calendar) ?? (hour >= context.workingHours.startHour && hour < context.workingHours.endHour)
        guard working,
              context.availableMinutes != 0 else { return false }
        if let scheduled = task.scheduledDate,
           scheduled > context.now,
           !task.isKeptInFront(at: context.now, calendar: context.calendar) { return false }
        if task.snoozeCount > 0, let next = task.nextSurfaceAt, next > context.now { return false }
        if let duration = task.estimatedDurationMinutes, let available = context.availableMinutes, duration > available { return false }
        return true
    }

    func reason(for task: TenoraTask, context: Context) -> String {
        if task.isKeptInFront(at: context.now, calendar: context.calendar) { return "You asked Tenora to keep this in front today." }
        if let capacityReason = capacityReason(for: task, context: context) { return capacityReason }
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

    private func keepInFrontWeight(_ task: TenoraTask, context: Context) -> Int {
        task.isKeptInFront(at: context.now, calendar: context.calendar) ? 120 : 0
    }

    private func capacityWeight(_ task: TenoraTask, context: Context) -> Int {
        switch context.capacityMode {
        case .balanced:
            return 0
        case .easyWin:
            var weight = task.hasCapacityTrait(.easyWin) ? 120 : 0
            if let duration = task.estimatedDurationMinutes {
                if duration <= 15 { weight += 70 }
                else if duration <= 30 { weight += 25 }
                else { weight -= 25 }
            }
            if task.nextStep?.isEmpty == false { weight += 25 }
            return weight
        case .interesting:
            return task.hasCapacityTrait(.interesting) ? 140 : 0
        case .important:
            var weight = 0
            if task.priority == .important { weight += 90 }
            if task.priority == .critical { weight += 140 }
            let importanceHorizon = context.calendar.date(byAdding: .day, value: 1, to: context.now) ?? context.now
            if let due = task.dueDate, due <= importanceHorizon {
                weight += 70
            }
            return weight
        case .mindless:
            var weight = task.hasCapacityTrait(.mindless) ? 140 : 0
            if let duration = task.estimatedDurationMinutes, duration <= 20 { weight += 25 }
            return weight
        case .quick:
            guard let duration = task.estimatedDurationMinutes else { return 0 }
            if duration <= 15 { return 140 }
            if duration <= 30 { return 40 }
            return -40
        case .momentum:
            var weight = task.status == .active ? 110 : 0
            if task.nextStep?.isEmpty == false { weight += 45 }
            if let worked = task.lastWorkedAt, context.now.timeIntervalSince(worked) <= 86_400 { weight += 65 }
            return weight
        }
    }

    private func capacityReason(for task: TenoraTask, context: Context) -> String? {
        switch context.capacityMode {
        case .balanced:
            return nil
        case .easyWin where task.hasCapacityTrait(.easyWin) || (task.estimatedDurationMinutes ?? .max) <= 15:
            return "You asked for an easy win, and this looks approachable right now."
        case .interesting where task.hasCapacityTrait(.interesting):
            return "You asked for something interesting, and this task is marked as engaging."
        case .important where task.priority != .normal || task.dueDate != nil:
            return "You asked to focus on what matters most."
        case .mindless where task.hasCapacityTrait(.mindless):
            return "You asked for something you can do without much thinking."
        case .quick where (task.estimatedDurationMinutes ?? .max) <= 15:
            return "You asked for something quick, and this should fit."
        case .momentum where task.status == .active || task.nextStep?.isEmpty == false || task.lastWorkedAt != nil:
            return "You have momentum, and this task already has a clear thread to follow."
        default:
            return "This is the closest fit for the capacity you chose."
        }
    }
}
