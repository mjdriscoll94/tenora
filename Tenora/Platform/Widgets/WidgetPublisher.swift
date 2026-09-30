import Foundation
import WidgetKit

@MainActor
enum WidgetPublisher {
    static func publish(tasks: [TenoraTask], events: [CalendarEvent], calendarKnown: Bool, focusedTaskID: UUID?) {
        let hours = AttentionPreferences.workingHours
        let defaults = UserDefaults.standard
        let snapshot = WidgetSnapshot(
            updatedAt: Date(), tasks: tasks, events: events, calendarKnown: calendarKnown,
            startHour: hours.startHour, endHour: hours.endHour,
            focusedTaskID: focusedTaskID, schedule: AttentionPreferences.schedule,
            capacityModeRaw: defaults.string(forKey: AttentionPreferences.capacityModeKey),
            capacitySelectedAt: defaults.double(forKey: AttentionPreferences.capacitySelectedAtKey)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: WidgetSnapshot.groupID)?.set(data, forKey: WidgetSnapshot.key)
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraNow")
    }
}
