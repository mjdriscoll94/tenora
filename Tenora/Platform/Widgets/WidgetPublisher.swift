import Foundation
import WidgetKit

@MainActor
enum WidgetPublisher {
    static func publish(
        tasks: [TenoraTask],
        events: [CalendarEvent],
        calendarKnown: Bool,
        focusedTaskID: UUID?,
        profileID: LocalProfileID = .offline,
        settings: SettingsRepository? = nil
    ) {
        let legacyDefaults = UserDefaults.standard
        let start = settings?.integer(for: .legacyWorkStart, default: 8) ?? AttentionPreferences.workingHours.startHour
        let end = settings?.integer(for: .legacyWorkEnd, default: 18) ?? AttentionPreferences.workingHours.endHour
        let scheduleJSON = settings?.string(for: .workingSchedule) ?? AttentionPreferences.scheduleKeyValue
        let snapshot = WidgetSnapshot(
            updatedAt: Date(), tasks: tasks, events: events, calendarKnown: calendarKnown,
            startHour: start, endHour: end,
            focusedTaskID: focusedTaskID,
            schedule: AttentionPreferences.schedule(from: scheduleJSON, fallback: WorkingHours(startHour: start, endHour: end)),
            capacityModeRaw: settings?.string(for: .capacityMode) ?? legacyDefaults.string(forKey: AttentionPreferences.capacityModeKey),
            capacitySelectedAt: settings?.double(for: .capacitySelectedAt, default: 0)
                ?? legacyDefaults.double(forKey: AttentionPreferences.capacitySelectedAtKey)
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let defaults = UserDefaults(suiteName: WidgetSnapshot.groupID)
        defaults?.set(profileID.rawValue, forKey: WidgetSnapshot.activeProfileKey)
        defaults?.set(data, forKey: WidgetSnapshot.storageKey(profileID: profileID.rawValue))
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraNow")
    }

    static func publishHabits(_ snapshot: HabitWidgetSnapshot, profileID: LocalProfileID = .offline) {
        snapshot.write(profileID: profileID.rawValue)
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraHabits")
    }
}
