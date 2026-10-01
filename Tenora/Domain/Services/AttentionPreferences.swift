import Foundation

enum AttentionPreferences {
    static let scheduleKey = "workingSchedule.v1"
    static let capacityModeKey = "attention.capacityMode"
    static let capacitySelectedAtKey = "attention.capacitySelectedAt"
    static let useAllCalendarsKey = "calendar.useAll"
    static let selectedCalendarIDsKey = "calendar.selectedIDs"
    static let meetingBufferMinutesKey = "calendar.meetingBufferMinutes"
    static let minimumGapMinutesKey = "calendar.minimumGapMinutes"
    static let taskRemindersEnabledKey = "reminders.taskEnabled"
    static let reminderLevelKey = "reminders.level"
    static let reminderStartMinuteKey = "reminders.startMinute"
    static let reminderEndMinuteKey = "reminders.endMinute"
    static let recoveryEnabledKey = "recovery.enabled"
    static let recoveryDelayKey = "recovery.delay"
    static var schedule: WorkingSchedule { schedule(from: UserDefaults.standard.string(forKey: scheduleKey) ?? "") }

    static func schedule(from json: String, fallback: WorkingHours? = nil) -> WorkingSchedule {
        if let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode(WorkingSchedule.self, from: data), decoded.isValid { return decoded }
        return WorkingSchedule(hours: fallback ?? workingHours)
    }

    static var workingHours: WorkingHours {
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "workStart") as? Int ?? 8
        let end = defaults.object(forKey: "workEnd") as? Int ?? 18
        guard (0...23).contains(start), (1...24).contains(end), start < end else { return WorkingHours() }
        return WorkingHours(startHour: start, endHour: end)
    }

    static func capacityMode(rawValue: String, selectedAt: Double, now: Date, calendar: Calendar = .current) -> TaskCapacityMode {
        guard selectedAt > 0,
              calendar.isDate(Date(timeIntervalSince1970: selectedAt), inSameDayAs: now),
              let mode = TaskCapacityMode(rawValue: rawValue) else { return .balanced }
        return mode
    }

    static var useAllCalendars: Bool {
        UserDefaults.standard.object(forKey: useAllCalendarsKey) as? Bool ?? true
    }

    static var selectedCalendarIDs: Set<String> {
        guard let data = UserDefaults.standard.data(forKey: selectedCalendarIDsKey),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    static func saveSelectedCalendarIDs(_ identifiers: Set<String>) {
        UserDefaults.standard.set(try? JSONEncoder().encode(identifiers.sorted()), forKey: selectedCalendarIDsKey)
    }

    static var meetingBufferMinutes: Int {
        UserDefaults.standard.object(forKey: meetingBufferMinutesKey) as? Int ?? 0
    }

    static var minimumGapMinutes: Int {
        UserDefaults.standard.object(forKey: minimumGapMinutesKey) as? Int ?? 15
    }

    static var taskRemindersEnabled: Bool {
        UserDefaults.standard.object(forKey: taskRemindersEnabledKey) as? Bool ?? true
    }

    static var reminderLevel: ReminderLevel {
        ReminderLevel(rawValue: UserDefaults.standard.string(forKey: reminderLevelKey) ?? "") ?? .standard
    }

    static var reminderStartMinute: Int {
        UserDefaults.standard.object(forKey: reminderStartMinuteKey) as? Int ?? 9 * 60
    }

    static var reminderEndMinute: Int {
        UserDefaults.standard.object(forKey: reminderEndMinuteKey) as? Int ?? 20 * 60
    }

    static var recoveryEnabled: Bool {
        UserDefaults.standard.object(forKey: recoveryEnabledKey) as? Bool ?? true
    }

    static var recoveryDelay: RecoveryPromptDelay {
        RecoveryPromptDelay(rawValue: UserDefaults.standard.string(forKey: recoveryDelayKey) ?? "") ?? .fifteenMinutes
    }

    static func shouldOfferRecovery(lastLeft: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard recoveryEnabled, now > lastLeft else { return false }
        switch recoveryDelay {
        case .fifteenMinutes: return now.timeIntervalSince(lastLeft) >= 15 * 60
        case .oneHour: return now.timeIntervalSince(lastLeft) >= 60 * 60
        case .nextDay: return !calendar.isDate(lastLeft, inSameDayAs: now)
        }
    }

    static func resetLocalPreferences() {
        let defaults = UserDefaults.standard
        [
            scheduleKey, capacityModeKey, capacitySelectedAtKey,
            useAllCalendarsKey, selectedCalendarIDsKey, meetingBufferMinutesKey, minimumGapMinutesKey,
            taskRemindersEnabledKey, reminderLevelKey, reminderStartMinuteKey, reminderEndMinuteKey,
            recoveryEnabledKey, recoveryDelayKey,
            "workStart", "workEnd", "lastLeftTenora", "reminderReservations", "pendingReminderActions"
        ].forEach(defaults.removeObject(forKey:))
    }
}

enum ReminderLevel: String, CaseIterable, Identifiable, Codable {
    case minimal
    case standard
    case frequent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimal: "Minimal"
        case .standard: "Standard"
        case .frequent: "Frequent"
        }
    }
    var dailyLimit: Int {
        switch self {
        case .minimal: 1
        case .standard: 2
        case .frequent: 3
        }
    }
}

enum RecoveryPromptDelay: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case nextDay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        case .nextDay: "The next day"
        }
    }
}
