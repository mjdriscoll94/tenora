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

    static func read() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func recommendation(at date: Date) -> TenoraTask? {
        guard date.timeIntervalSince(updatedAt) < 6 * 3600 else { return nil }
        let snapshot = AvailabilityEngine().snapshot(at: date, events: events,
            workingHours: WorkingHours(startHour: startHour, endHour: endHour))
        guard snapshot.currentEvent == nil, snapshot.availableMinutes != nil else { return nil }
        let context = TaskPriorityEngine.Context(now: date, availableMinutes: calendarKnown ? snapshot.availableMinutes : nil,
            workingHours: WorkingHours(startHour: startHour, endHour: endHour))
        if let focused = tasks.first(where: { $0.id == focusedTaskID }), TaskPriorityEngine().isEligible(focused, context: context) { return focused }
        return TaskPriorityEngine().recommendation(from: tasks, context: context)
    }
}
