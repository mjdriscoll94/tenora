import Foundation

struct WidgetSnapshot: Codable {
    static let groupID = "group.com.tenora.app"
    static let key = "tenora.widget.snapshot.v1"
    let updatedAt: Date
    let tasks: [TenoraTask]
    let events: [CalendarEvent]
    let calendarKnown: Bool
    let startHour: Int
    let endHour: Int
    var focusedTaskID: UUID? = nil
    var schedule: WorkingSchedule? = nil
    var capacityModeRaw: String? = nil
    var capacitySelectedAt: Double = 0

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func recommendation(at date: Date) -> TenoraTask? {
        guard date.timeIntervalSince(updatedAt) < 6 * 3600 else { return nil }
        let snapshot = AvailabilityEngine().snapshot(at: date, events: events,
            workingHours: WorkingHours(startHour: startHour, endHour: endHour), schedule: schedule)
        let capacityMode: TaskCapacityMode = {
            guard capacitySelectedAt > 0,
                  Calendar.current.isDate(Date(timeIntervalSince1970: capacitySelectedAt), inSameDayAs: date),
                  let raw = capacityModeRaw,
                  let mode = TaskCapacityMode(rawValue: raw) else { return .balanced }
            return mode
        }()
        let context = TaskPriorityEngine.Context(now: date, availableMinutes: calendarKnown ? snapshot.availableMinutes : nil,
            workingHours: WorkingHours(startHour: startHour, endHour: endHour), schedule: schedule, capacityMode: capacityMode)
        let engine = TaskPriorityEngine()
        if let focused = tasks.first(where: { $0.id == focusedTaskID }), engine.isEligible(focused, context: context) { return focused }
        if let kept = tasks
            .filter({ task in
                task.isKeptInFront(at: date)
                    && !(task.snoozeCount > 0 && (task.nextSurfaceAt ?? .distantPast) > date)
            })
            .max(by: { lhs, rhs in
                let lhsScore = engine.score(for: lhs, context: context)
                let rhsScore = engine.score(for: rhs, context: context)
                return lhsScore == rhsScore ? lhs.createdAt > rhs.createdAt : lhsScore < rhsScore
            }) {
            return kept
        }
        guard snapshot.currentEvent == nil, snapshot.availableMinutes != nil else { return nil }
        return engine.recommendation(from: tasks, context: context)
    }
}
