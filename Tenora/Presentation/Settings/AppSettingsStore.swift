import Foundation

/// The observable presentation boundary for profile-scoped preferences.
/// Views never need to know how or where a preference is persisted.
@MainActor
final class AppSettingsStore: ObservableObject {
    let repository: SettingsRepository

    @Published var workingScheduleJSON: String { didSet { repository.set(workingScheduleJSON, for: .workingSchedule) } }
    @Published var legacyWorkStart: Int { didSet { repository.set(legacyWorkStart, for: .legacyWorkStart) } }
    @Published var legacyWorkEnd: Int { didSet { repository.set(legacyWorkEnd, for: .legacyWorkEnd) } }
    @Published var capacityModeRaw: String { didSet { repository.set(capacityModeRaw, for: .capacityMode) } }
    @Published var capacitySelectedAt: Double { didSet { repository.set(capacitySelectedAt, for: .capacitySelectedAt) } }
    @Published var useAllCalendars: Bool { didSet { repository.set(useAllCalendars, for: .useAllCalendars) } }
    @Published var selectedCalendarIDs: Set<String> { didSet { saveCalendarIDs() } }
    @Published var meetingBufferMinutes: Int { didSet { repository.set(meetingBufferMinutes, for: .meetingBufferMinutes) } }
    @Published var minimumGapMinutes: Int { didSet { repository.set(minimumGapMinutes, for: .minimumGapMinutes) } }
    @Published var taskRemindersEnabled: Bool { didSet { repository.set(taskRemindersEnabled, for: .taskRemindersEnabled) } }
    @Published var reminderLevelRaw: String { didSet { repository.set(reminderLevelRaw, for: .reminderLevel) } }
    @Published var reminderStartMinute: Int { didSet { repository.set(reminderStartMinute, for: .reminderStartMinute) } }
    @Published var reminderEndMinute: Int { didSet { repository.set(reminderEndMinute, for: .reminderEndMinute) } }
    @Published var recoveryEnabled: Bool { didSet { repository.set(recoveryEnabled, for: .recoveryEnabled) } }
    @Published var recoveryDelayRaw: String { didSet { repository.set(recoveryDelayRaw, for: .recoveryDelay) } }
    @Published var lastLeft: Double { didSet { repository.set(lastLeft, for: .lastLeft) } }
    @Published var onboardingCompleted: Bool { didSet { repository.set(onboardingCompleted, for: .onboardingCompleted) } }
    @Published var habitsIntroSeen: Bool { didSet { repository.set(habitsIntroSeen, for: .habitsIntroSeen) } }

    init(repository: SettingsRepository) {
        self.repository = repository
        workingScheduleJSON = repository.string(for: .workingSchedule) ?? ""
        legacyWorkStart = repository.integer(for: .legacyWorkStart, default: 8)
        legacyWorkEnd = repository.integer(for: .legacyWorkEnd, default: 18)
        capacityModeRaw = repository.string(for: .capacityMode) ?? TaskCapacityMode.balanced.rawValue
        capacitySelectedAt = repository.double(for: .capacitySelectedAt, default: 0)
        useAllCalendars = repository.bool(for: .useAllCalendars, default: true)
        if let data = repository.data(for: .selectedCalendarIDs),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            selectedCalendarIDs = Set(values)
        } else {
            selectedCalendarIDs = []
        }
        meetingBufferMinutes = repository.integer(for: .meetingBufferMinutes, default: 0)
        minimumGapMinutes = repository.integer(for: .minimumGapMinutes, default: 15)
        taskRemindersEnabled = repository.bool(for: .taskRemindersEnabled, default: true)
        reminderLevelRaw = repository.string(for: .reminderLevel) ?? ReminderLevel.standard.rawValue
        reminderStartMinute = repository.integer(for: .reminderStartMinute, default: 9 * 60)
        reminderEndMinute = repository.integer(for: .reminderEndMinute, default: 20 * 60)
        recoveryEnabled = repository.bool(for: .recoveryEnabled, default: true)
        recoveryDelayRaw = repository.string(for: .recoveryDelay) ?? RecoveryPromptDelay.fifteenMinutes.rawValue
        lastLeft = repository.double(for: .lastLeft, default: 0)
        onboardingCompleted = repository.bool(for: .onboardingCompleted, default: false)
        habitsIntroSeen = repository.bool(for: .habitsIntroSeen, default: false)
    }

    var schedule: WorkingSchedule {
        AttentionPreferences.schedule(
            from: workingScheduleJSON,
            fallback: WorkingHours(startHour: legacyWorkStart, endHour: legacyWorkEnd)
        )
    }

    func capacityMode(at date: Date) -> TaskCapacityMode {
        AttentionPreferences.capacityMode(rawValue: capacityModeRaw, selectedAt: capacitySelectedAt, now: date)
    }

    func shouldOfferRecovery(now: Date) -> Bool {
        guard recoveryEnabled, lastLeft > 0 else { return false }
        let left = Date(timeIntervalSince1970: lastLeft)
        let delay = RecoveryPromptDelay(rawValue: recoveryDelayRaw) ?? .fifteenMinutes
        switch delay {
        case .fifteenMinutes: return now.timeIntervalSince(left) >= 15 * 60
        case .oneHour: return now.timeIntervalSince(left) >= 60 * 60
        case .nextDay: return !Calendar.current.isDate(left, inSameDayAs: now)
        }
    }

    func reset() {
        repository.removeAll()
        workingScheduleJSON = ""
        legacyWorkStart = 8
        legacyWorkEnd = 18
        capacityModeRaw = TaskCapacityMode.balanced.rawValue
        capacitySelectedAt = 0
        useAllCalendars = true
        selectedCalendarIDs = []
        meetingBufferMinutes = 0
        minimumGapMinutes = 15
        taskRemindersEnabled = true
        reminderLevelRaw = ReminderLevel.standard.rawValue
        reminderStartMinute = 9 * 60
        reminderEndMinute = 20 * 60
        recoveryEnabled = true
        recoveryDelayRaw = RecoveryPromptDelay.fifteenMinutes.rawValue
        lastLeft = 0
        onboardingCompleted = false
        habitsIntroSeen = false
    }

    func reload() {
        workingScheduleJSON = repository.string(for: .workingSchedule) ?? ""
        legacyWorkStart = repository.integer(for: .legacyWorkStart, default: 8)
        legacyWorkEnd = repository.integer(for: .legacyWorkEnd, default: 18)
        capacityModeRaw = repository.string(for: .capacityMode) ?? TaskCapacityMode.balanced.rawValue
        capacitySelectedAt = repository.double(for: .capacitySelectedAt, default: 0)
        useAllCalendars = repository.bool(for: .useAllCalendars, default: true)
        if let data = repository.data(for: .selectedCalendarIDs),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            selectedCalendarIDs = Set(values)
        } else {
            selectedCalendarIDs = []
        }
        meetingBufferMinutes = repository.integer(for: .meetingBufferMinutes, default: 0)
        minimumGapMinutes = repository.integer(for: .minimumGapMinutes, default: 15)
        taskRemindersEnabled = repository.bool(for: .taskRemindersEnabled, default: true)
        reminderLevelRaw = repository.string(for: .reminderLevel) ?? ReminderLevel.standard.rawValue
        reminderStartMinute = repository.integer(for: .reminderStartMinute, default: 9 * 60)
        reminderEndMinute = repository.integer(for: .reminderEndMinute, default: 20 * 60)
        recoveryEnabled = repository.bool(for: .recoveryEnabled, default: true)
        recoveryDelayRaw = repository.string(for: .recoveryDelay) ?? RecoveryPromptDelay.fifteenMinutes.rawValue
        lastLeft = repository.double(for: .lastLeft, default: 0)
        onboardingCompleted = repository.bool(for: .onboardingCompleted, default: false)
        habitsIntroSeen = repository.bool(for: .habitsIntroSeen, default: false)
    }

    private func saveCalendarIDs() {
        repository.set(try? JSONEncoder().encode(selectedCalendarIDs.sorted()), for: .selectedCalendarIDs)
    }
}
