import CryptoKit
import Foundation
import SwiftData

struct TenoraBackupEnvelope: Codable, Equatable {
    static let format = "com.tenora.backup"
    static let currentVersion = 1

    let format: String
    let version: Int
    let checksum: String
    /// Stored as bytes so the checksum always covers exactly what will be decoded.
    /// This avoids non-deterministic ordering from set-backed fields such as weekdays.
    let payload: Data
}

struct TenoraBackupPayload: Codable, Equatable {
    let exportedAt: Date
    let sourceAppVersion: String
    let sourceBuild: String
    let tasks: [TenoraTask]
    let habits: [Habit]
    let habitCompletions: [HabitCompletion]
    let playerProgress: [PlayerProgressBackup]
    let gameUnlocks: [GameUnlockBackup]
    let transitionPlans: [TransitionPlan]
    let preferences: TenoraPreferenceBackup
}

struct PlayerProgressBackup: Codable, Equatable {
    let recordID: String
    let totalXP: Int
    let level: Int
    let xpIntoLevel: Int
    let xpForNextLevel: Int
    let totalCompletions: Int
    let currentMomentum: Int
    let longestMomentum: Int
    let perfectDays: Int

    init(_ stored: StoredPlayerProgress) {
        recordID = stored.recordID
        totalXP = stored.totalXP
        level = stored.level
        xpIntoLevel = stored.xpIntoLevel
        xpForNextLevel = stored.xpForNextLevel
        totalCompletions = stored.totalCompletions
        currentMomentum = stored.currentMomentum
        longestMomentum = stored.longestMomentum
        perfectDays = stored.perfectDays
    }

    var model: StoredPlayerProgress {
        StoredPlayerProgress(
            recordID: recordID,
            progress: PlayerProgress(
                totalXP: totalXP,
                level: level,
                xpIntoLevel: xpIntoLevel,
                xpForNextLevel: xpForNextLevel,
                totalCompletions: totalCompletions,
                currentMomentum: currentMomentum,
                longestMomentum: longestMomentum,
                perfectDays: perfectDays
            )
        )
    }
}

struct GameUnlockBackup: Codable, Equatable {
    let id: String
    let kind: String
    let unlockedAt: Date

    init(_ stored: StoredGameUnlock) {
        id = stored.id
        kind = stored.kind
        unlockedAt = stored.unlockedAt
    }

    var model: StoredGameUnlock { StoredGameUnlock(id: id, kind: kind, unlockedAt: unlockedAt) }
}

struct TenoraPreferenceBackup: Codable, Equatable {
    let workingScheduleJSON: String?
    let legacyWorkStart: Int?
    let legacyWorkEnd: Int?
    let capacityMode: String?
    let capacitySelectedAt: Double?
    let useAllCalendars: Bool?
    let selectedCalendarIDs: [String]
    let meetingBufferMinutes: Int?
    let minimumGapMinutes: Int?
    let taskRemindersEnabled: Bool?
    let reminderLevel: String?
    let reminderStartMinute: Int?
    let reminderEndMinute: Int?
    let recoveryEnabled: Bool?
    let recoveryDelay: String?
    var focusedTaskID: UUID?
    let lastLeftTimeInterval: Double?
    let accountOnboardingCompleted: Bool?
    let habitsIntroSeen: Bool?
    let agentBridgeSharingEnabled: Bool?
    let agentBridgeIncludeNotes: Bool?
    let agentBridgeIncludeCalendar: Bool?
    let agentBridgeLastSyncedAt: Date?

    init(defaults: UserDefaults) {
        workingScheduleJSON = defaults.string(forKey: AttentionPreferences.scheduleKey)
        legacyWorkStart = defaults.object(forKey: "workStart") as? Int
        legacyWorkEnd = defaults.object(forKey: "workEnd") as? Int
        capacityMode = defaults.string(forKey: AttentionPreferences.capacityModeKey)
        capacitySelectedAt = defaults.object(forKey: AttentionPreferences.capacitySelectedAtKey) as? Double
        useAllCalendars = defaults.object(forKey: AttentionPreferences.useAllCalendarsKey) as? Bool
        if let data = defaults.data(forKey: AttentionPreferences.selectedCalendarIDsKey),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            selectedCalendarIDs = values.sorted()
        } else {
            selectedCalendarIDs = []
        }
        meetingBufferMinutes = defaults.object(forKey: AttentionPreferences.meetingBufferMinutesKey) as? Int
        minimumGapMinutes = defaults.object(forKey: AttentionPreferences.minimumGapMinutesKey) as? Int
        taskRemindersEnabled = defaults.object(forKey: AttentionPreferences.taskRemindersEnabledKey) as? Bool
        reminderLevel = defaults.string(forKey: AttentionPreferences.reminderLevelKey)
        reminderStartMinute = defaults.object(forKey: AttentionPreferences.reminderStartMinuteKey) as? Int
        reminderEndMinute = defaults.object(forKey: AttentionPreferences.reminderEndMinuteKey) as? Int
        recoveryEnabled = defaults.object(forKey: AttentionPreferences.recoveryEnabledKey) as? Bool
        recoveryDelay = defaults.string(forKey: AttentionPreferences.recoveryDelayKey)
        focusedTaskID = defaults.string(forKey: "focusedTask").flatMap(UUID.init(uuidString:))
        lastLeftTimeInterval = defaults.object(forKey: "lastLeftTenora") as? Double
        accountOnboardingCompleted = defaults.object(forKey: "account.onboardingCompleted") as? Bool
        habitsIntroSeen = defaults.object(forKey: "habits.intro.seen") as? Bool
        agentBridgeSharingEnabled = defaults.object(forKey: "agentBridge.sharingEnabled") as? Bool
        agentBridgeIncludeNotes = defaults.object(forKey: "agentBridge.includeNotes") as? Bool
        agentBridgeIncludeCalendar = defaults.object(forKey: "agentBridge.includeCalendar") as? Bool
        agentBridgeLastSyncedAt = defaults.object(forKey: "agentBridge.lastSyncedAt") as? Date
    }

    func apply(to defaults: UserDefaults) {
        Self.keys.forEach(defaults.removeObject(forKey:))
        set(workingScheduleJSON, key: AttentionPreferences.scheduleKey, defaults: defaults)
        set(legacyWorkStart, key: "workStart", defaults: defaults)
        set(legacyWorkEnd, key: "workEnd", defaults: defaults)
        set(capacityMode, key: AttentionPreferences.capacityModeKey, defaults: defaults)
        set(capacitySelectedAt, key: AttentionPreferences.capacitySelectedAtKey, defaults: defaults)
        set(useAllCalendars, key: AttentionPreferences.useAllCalendarsKey, defaults: defaults)
        if !selectedCalendarIDs.isEmpty {
            defaults.set(try? JSONEncoder().encode(selectedCalendarIDs.sorted()), forKey: AttentionPreferences.selectedCalendarIDsKey)
        }
        set(meetingBufferMinutes, key: AttentionPreferences.meetingBufferMinutesKey, defaults: defaults)
        set(minimumGapMinutes, key: AttentionPreferences.minimumGapMinutesKey, defaults: defaults)
        set(taskRemindersEnabled, key: AttentionPreferences.taskRemindersEnabledKey, defaults: defaults)
        set(reminderLevel, key: AttentionPreferences.reminderLevelKey, defaults: defaults)
        set(reminderStartMinute, key: AttentionPreferences.reminderStartMinuteKey, defaults: defaults)
        set(reminderEndMinute, key: AttentionPreferences.reminderEndMinuteKey, defaults: defaults)
        set(recoveryEnabled, key: AttentionPreferences.recoveryEnabledKey, defaults: defaults)
        set(recoveryDelay, key: AttentionPreferences.recoveryDelayKey, defaults: defaults)
        set(focusedTaskID?.uuidString, key: "focusedTask", defaults: defaults)
        set(lastLeftTimeInterval, key: "lastLeftTenora", defaults: defaults)
        set(accountOnboardingCompleted, key: "account.onboardingCompleted", defaults: defaults)
        set(habitsIntroSeen, key: "habits.intro.seen", defaults: defaults)
        set(agentBridgeSharingEnabled, key: "agentBridge.sharingEnabled", defaults: defaults)
        set(agentBridgeIncludeNotes, key: "agentBridge.includeNotes", defaults: defaults)
        set(agentBridgeIncludeCalendar, key: "agentBridge.includeCalendar", defaults: defaults)
        set(agentBridgeLastSyncedAt, key: "agentBridge.lastSyncedAt", defaults: defaults)
    }

    private func set(_ value: Any?, key: String, defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(value, forKey: key)
    }

    private static let keys = [
        AttentionPreferences.scheduleKey, "workStart", "workEnd",
        AttentionPreferences.capacityModeKey, AttentionPreferences.capacitySelectedAtKey,
        AttentionPreferences.useAllCalendarsKey, AttentionPreferences.selectedCalendarIDsKey,
        AttentionPreferences.meetingBufferMinutesKey, AttentionPreferences.minimumGapMinutesKey,
        AttentionPreferences.taskRemindersEnabledKey, AttentionPreferences.reminderLevelKey,
        AttentionPreferences.reminderStartMinuteKey, AttentionPreferences.reminderEndMinuteKey,
        AttentionPreferences.recoveryEnabledKey, AttentionPreferences.recoveryDelayKey,
        "focusedTask", "lastLeftTenora", "account.onboardingCompleted", "habits.intro.seen",
        "agentBridge.sharingEnabled", "agentBridge.includeNotes", "agentBridge.includeCalendar",
        "agentBridge.lastSyncedAt"
    ]
}

@MainActor
enum TenoraDataArchive {
    static func make(
        context: ModelContext,
        transitionPlans: [TransitionPlan],
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: Date = Date()
    ) throws -> Data {
        let tasks = try context.fetch(
            FetchDescriptor<StoredTask>(sortBy: [SortDescriptor(\.createdAt)])
        ).map(\.domainModel)
        var preferences = TenoraPreferenceBackup(defaults: defaults)
        if let focus = preferences.focusedTaskID,
           !tasks.contains(where: { $0.id == focus && ![.completed, .archived].contains($0.status) }) {
            preferences.focusedTaskID = nil
        }
        let payload = TenoraBackupPayload(
            exportedAt: now,
            sourceAppVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            sourceBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            tasks: tasks,
            habits: try context.fetch(FetchDescriptor<StoredHabit>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domainModel),
            habitCompletions: try context.fetch(FetchDescriptor<StoredHabitCompletion>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domainModel),
            playerProgress: try context.fetch(FetchDescriptor<StoredPlayerProgress>(sortBy: [SortDescriptor(\.recordID)])).map(PlayerProgressBackup.init),
            gameUnlocks: try context.fetch(FetchDescriptor<StoredGameUnlock>(sortBy: [SortDescriptor(\.id)])).map(GameUnlockBackup.init),
            transitionPlans: transitionPlans.sorted(by: { $0.id < $1.id }),
            preferences: preferences
        )
        try validate(payload)
        let payloadData = try encodePayload(payload)
        let checksum = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
        let envelope = TenoraBackupEnvelope(
            format: TenoraBackupEnvelope.format,
            version: TenoraBackupEnvelope.currentVersion,
            checksum: checksum,
            payload: payloadData
        )
        return try encoder().encode(envelope)
    }

    static func decode(_ data: Data) throws -> TenoraBackupPayload {
        let envelope: TenoraBackupEnvelope
        do {
            envelope = try decoder().decode(TenoraBackupEnvelope.self, from: data)
        } catch {
            return try decodeLegacy(data)
        }
        guard envelope.format == TenoraBackupEnvelope.format else { throw TenoraBackupError.unsupportedFormat }
        guard envelope.version == TenoraBackupEnvelope.currentVersion else { throw TenoraBackupError.unsupportedVersion }
        let checksum = SHA256.hash(data: envelope.payload).map { String(format: "%02x", $0) }.joined()
        guard checksum == envelope.checksum else { throw TenoraBackupError.checksumMismatch }
        let payload = try decoder().decode(TenoraBackupPayload.self, from: envelope.payload)
        try validate(payload)
        return payload
    }

    @MainActor
    static func restore(
        _ payload: TenoraBackupPayload,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        profileID: LocalProfileID = .offline
    ) throws {
        try validate(payload)
        // Exercise every model insertion against an isolated store before touching
        // the live context. A malformed or future-incompatible backup fails here.
        let stagingContainer = try TenoraModelContainerFactory.makeInMemory()
        try insert(payload, into: stagingContainer.mainContext)

        try context.transaction {
            for item in try context.fetch(FetchDescriptor<StoredTask>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<StoredHabit>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<StoredHabitCompletion>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<StoredPlayerProgress>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<StoredGameUnlock>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<StoredSyncMetadata>()) { context.delete(item) }

            try insert(payload, into: context)
        }
        _ = try PersonalSyncMetadataStore(modelContext: context).backfill(profileID: profileID)
        payload.preferences.apply(to: defaults)
    }

    @discardableResult
    static func savePreRestoreCopy(_ data: Data) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "Tenora Recovery Backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Pre-Restore Backup.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func validate(_ payload: TenoraBackupPayload) throws {
        try requireUnique(payload.tasks.map(\.id), field: "task IDs")
        try requireUnique(payload.habits.map(\.id), field: "habit IDs")
        try requireUnique(payload.habitCompletions.map(\.id), field: "habit completion IDs")
        try requireUnique(payload.playerProgress.map(\.recordID), field: "progress record IDs")
        try requireUnique(payload.gameUnlocks.map(\.id), field: "game unlock IDs")
        try requireUnique(payload.transitionPlans.map(\.id), field: "transition plan IDs")
        guard payload.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              payload.habits.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TenoraBackupError.invalidRecords("Tasks and habits must have names.")
        }
        let habitIDs = Set(payload.habits.map(\.id))
        guard payload.habitCompletions.allSatisfy({ habitIDs.contains($0.habitID) }) else {
            throw TenoraBackupError.invalidRecords("The backup contains a habit check-in without its habit.")
        }
        if let focus = payload.preferences.focusedTaskID,
           !payload.tasks.contains(where: { $0.id == focus && ![.completed, .archived].contains($0.status) }) {
            throw TenoraBackupError.invalidRecords("The focused task is missing or no longer active.")
        }
    }

    private static func requireUnique<T: Hashable>(_ values: [T], field: String) throws {
        guard Set(values).count == values.count else {
            throw TenoraBackupError.invalidRecords("The backup contains duplicate \(field).")
        }
    }

    private static func insert(_ payload: TenoraBackupPayload, into context: ModelContext) throws {
        payload.tasks.forEach { context.insert(StoredTask(task: $0)) }
        payload.habits.forEach { context.insert(StoredHabit(habit: $0)) }
        payload.habitCompletions.forEach { context.insert(StoredHabitCompletion(completion: $0)) }
        payload.playerProgress.forEach { context.insert($0.model) }
        payload.gameUnlocks.forEach { context.insert($0.model) }
        try context.save()
    }

    private static func decodeLegacy(_ data: Data) throws -> TenoraBackupPayload {
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? legacyDecoder.decode(LegacyTenoraExport.self, from: data) else {
            throw TenoraBackupError.unsupportedFormat
        }
        let suiteName = "com.tenora.legacy-import.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        if let scheduleData = try? JSONEncoder().encode(legacy.workingSchedule),
           let scheduleJSON = String(data: scheduleData, encoding: .utf8) {
            defaults.set(scheduleJSON, forKey: AttentionPreferences.scheduleKey)
        }
        defaults.set(legacy.reminderLevel, forKey: AttentionPreferences.reminderLevelKey)
        defaults.set(legacy.reminderStartMinute, forKey: AttentionPreferences.reminderStartMinuteKey)
        defaults.set(legacy.reminderEndMinute, forKey: AttentionPreferences.reminderEndMinuteKey)
        defaults.set(legacy.recoveryDelay, forKey: AttentionPreferences.recoveryDelayKey)
        let payload = TenoraBackupPayload(
            exportedAt: legacy.exportedAt,
            sourceAppVersion: "legacy-export",
            sourceBuild: "unknown",
            tasks: legacy.tasks,
            habits: legacy.habits,
            habitCompletions: legacy.habitCompletions,
            playerProgress: [],
            gameUnlocks: [],
            transitionPlans: legacy.transitionPlans,
            preferences: TenoraPreferenceBackup(defaults: defaults)
        )
        try validate(payload)
        return payload
    }

    private static func encodePayload(_ payload: TenoraBackupPayload) throws -> Data { try encoder().encode(payload) }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum TenoraBackupError: LocalizedError, Equatable {
    case unsupportedFormat
    case unsupportedVersion
    case checksumMismatch
    case invalidRecords(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "That file isn't a Tenora backup."
        case .unsupportedVersion: "This backup was created by an unsupported Tenora version."
        case .checksumMismatch: "The backup appears to be incomplete or changed."
        case .invalidRecords(let message): message
        }
    }
}

private struct LegacyTenoraExport: Codable {
    let exportedAt: Date
    let tasks: [TenoraTask]
    let habits: [Habit]
    let habitCompletions: [HabitCompletion]
    let transitionPlans: [TransitionPlan]
    let workingSchedule: WorkingSchedule
    let reminderLevel: String
    let reminderStartMinute: Int
    let reminderEndMinute: Int
    let recoveryDelay: String
}
