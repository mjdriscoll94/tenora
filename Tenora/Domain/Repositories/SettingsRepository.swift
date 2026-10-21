import Foundation

enum TenoraSettingKey: String, CaseIterable, Sendable {
    case workingSchedule = "workingSchedule.v1"
    case legacyWorkStart = "workStart"
    case legacyWorkEnd = "workEnd"
    case capacityMode = "attention.capacityMode"
    case capacitySelectedAt = "attention.capacitySelectedAt"
    case useAllCalendars = "calendar.useAll"
    case selectedCalendarIDs = "calendar.selectedIDs"
    case meetingBufferMinutes = "calendar.meetingBufferMinutes"
    case minimumGapMinutes = "calendar.minimumGapMinutes"
    case taskRemindersEnabled = "reminders.taskEnabled"
    case reminderLevel = "reminders.level"
    case reminderStartMinute = "reminders.startMinute"
    case reminderEndMinute = "reminders.endMinute"
    case recoveryEnabled = "recovery.enabled"
    case recoveryDelay = "recovery.delay"
    case focusedTaskID = "focusedTask"
    case lastLeft = "lastLeftTenora"
    case transitionPlans = "transitionPlans"
    case onboardingCompleted = "account.onboardingCompleted"
    case habitsIntroSeen = "habits.intro.seen"
    case reminderReservations = "reminderReservations"
    case pendingReminderActions = "pendingReminderActions"
}

@MainActor
protocol SettingsRepository: AnyObject {
    var profileID: LocalProfileID { get }
    func object(for key: TenoraSettingKey) -> Any?
    func set(_ value: Any?, for key: TenoraSettingKey)
    func remove(_ key: TenoraSettingKey)
    func removeAll()
    func refreshFromLegacyStore()
}

extension SettingsRepository {
    func refreshFromLegacyStore() {}
    func string(for key: TenoraSettingKey) -> String? { object(for: key) as? String }
    func data(for key: TenoraSettingKey) -> Data? { object(for: key) as? Data }
    func bool(for key: TenoraSettingKey, default fallback: Bool) -> Bool {
        object(for: key) as? Bool ?? fallback
    }
    func integer(for key: TenoraSettingKey, default fallback: Int) -> Int {
        object(for: key) as? Int ?? fallback
    }
    func double(for key: TenoraSettingKey, default fallback: Double) -> Double {
        object(for: key) as? Double ?? fallback
    }
}
