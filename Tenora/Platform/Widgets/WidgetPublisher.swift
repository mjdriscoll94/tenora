import Foundation
import WidgetKit

@MainActor
enum WidgetPublisher {
    static func publish(tasks: [TenoraTask], events: [CalendarEvent], calendarKnown: Bool) {
        let snapshot = WidgetSnapshot(updatedAt: Date(), tasks: tasks, events: events, calendarKnown: calendarKnown, startHour: 8, endHour: 18)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: WidgetSnapshot.groupID)?.set(data, forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraNow")
    }
}
