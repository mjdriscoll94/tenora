import Foundation
import WidgetKit

@MainActor
enum WidgetPublisher {
    static func publish(tasks: [TenoraTask], events: [CalendarEvent], calendarKnown: Bool, focusedTaskID: UUID?) {
        let hours = AttentionPreferences.workingHours
        let snapshot = WidgetSnapshot(updatedAt: Date(), tasks: tasks, events: events, calendarKnown: calendarKnown, startHour: hours.startHour, endHour: hours.endHour, focusedTaskID: focusedTaskID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: WidgetSnapshot.groupID)?.set(data, forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraNow")
    }
}
