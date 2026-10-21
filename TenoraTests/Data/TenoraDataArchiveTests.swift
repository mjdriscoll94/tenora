import Foundation
import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class TenoraDataArchiveTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for suite in defaultsSuites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        containers.removeAll()
        super.tearDown()
    }

    func testBackupRoundTripPreservesAllLocalDataAndPreferences() throws {
        let source = try makeContainer()
        let sourceDefaults = makeDefaults()
        let destinationDefaults = makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TenoraTask(
            title: "Submit forms",
            notes: "Keep the originals",
            createdAt: now,
            status: .active,
            dueDate: now.addingTimeInterval(3_600),
            estimatedDurationMinutes: 25,
            priority: .important,
            tags: ["family", "admin"],
            nextStep: "Find the envelope",
            lastWorkedAt: now,
            keepInFrontUntil: now.addingTimeInterval(86_400)
        )
        let habit = Habit(
            name: "Take medication",
            details: "With breakfast",
            iconName: "habit_icon_health",
            colorIdentifier: "forest",
            createdAt: now.addingTimeInterval(-86_400),
            difficulty: .easy,
            reminderMinute: 8 * 60
        )
        let completion = HabitCompletion(
            habitID: habit.id,
            completionDate: now,
            xpAwarded: 15,
            createdAt: now
        )
        let legacyProgress = PlayerProgress(
            totalXP: 2_450,
            level: 19,
            xpIntoLevel: 75,
            xpForNextLevel: 200,
            totalCompletions: 42,
            currentMomentum: 6,
            longestMomentum: 11,
            perfectDays: 8
        )
        let unlock = StoredGameUnlock(id: "garden.arch", kind: "decoration", unlockedAt: now)
        let transition = TransitionPlan(
            eventID: "calendar-event-1",
            eventTitle: "Dentist",
            eventStart: now.addingTimeInterval(7_200),
            leaveLeadMinutes: 20,
            wrapUpLeadMinutes: 15
        )

        source.mainContext.insert(StoredTask(task: task))
        source.mainContext.insert(StoredHabit(habit: habit))
        source.mainContext.insert(StoredHabitCompletion(completion: completion))
        source.mainContext.insert(StoredPlayerProgress(progress: legacyProgress))
        source.mainContext.insert(unlock)
        try source.mainContext.save()

        sourceDefaults.set(task.id.uuidString, forKey: "focusedTask")
        sourceDefaults.set("low", forKey: AttentionPreferences.capacityModeKey)
        sourceDefaults.set(true, forKey: AttentionPreferences.taskRemindersEnabledKey)
        sourceDefaults.set(["work", "family"], forKey: "test.unrelated")
        sourceDefaults.set(
            try JSONEncoder().encode(["calendar-b", "calendar-a"]),
            forKey: AttentionPreferences.selectedCalendarIDsKey
        )

        let data = try TenoraDataArchive.make(
            context: source.mainContext,
            transitionPlans: [transition],
            defaults: sourceDefaults,
            now: now
        )
        let payload = try TenoraDataArchive.decode(data)

        let destination = try makeContainer()
        destination.mainContext.insert(StoredTask(task: TenoraTask(title: "Replace me")))
        try destination.mainContext.save()
        destinationDefaults.set("keep", forKey: "test.unrelated")
        try TenoraDataArchive.restore(payload, context: destination.mainContext, defaults: destinationDefaults)

        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<StoredTask>()).map(\.domainModel), [task])
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<StoredHabit>()).map(\.domainModel), [habit])
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<StoredHabitCompletion>()).map(\.domainModel), [completion])
        let restoredProgress = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<StoredPlayerProgress>()).first)
        XCTAssertEqual(PlayerProgressBackup(restoredProgress), PlayerProgressBackup(StoredPlayerProgress(progress: legacyProgress)))
        let restoredUnlock = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<StoredGameUnlock>()).first)
        XCTAssertEqual(GameUnlockBackup(restoredUnlock), GameUnlockBackup(unlock))
        XCTAssertEqual(payload.transitionPlans, [transition])
        XCTAssertEqual(destinationDefaults.string(forKey: "focusedTask"), task.id.uuidString)
        XCTAssertEqual(destinationDefaults.string(forKey: AttentionPreferences.capacityModeKey), "low")
        XCTAssertEqual(destinationDefaults.string(forKey: "test.unrelated"), "keep")
        let selected = try XCTUnwrap(destinationDefaults.data(forKey: AttentionPreferences.selectedCalendarIDsKey))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: selected), ["calendar-a", "calendar-b"])
    }

    func testChangedBackupIsRejectedBeforeRestore() throws {
        let container = try makeContainer()
        container.mainContext.insert(StoredTask(task: TenoraTask(title: "Original")))
        try container.mainContext.save()
        let data = try TenoraDataArchive.make(
            context: container.mainContext,
            transitionPlans: [],
            defaults: makeDefaults()
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(TenoraBackupEnvelope.self, from: data)
        var changedPayload = envelope.payload
        changedPayload[changedPayload.startIndex] ^= 0x01
        let changedEnvelope = TenoraBackupEnvelope(
            format: envelope.format,
            version: envelope.version,
            checksum: envelope.checksum,
            payload: changedPayload
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let changedData = try encoder.encode(changedEnvelope)

        XCTAssertThrowsError(try TenoraDataArchive.decode(changedData)) { error in
            XCTAssertEqual(error as? TenoraBackupError, .checksumMismatch)
        }
    }

    func testOrphanHabitCompletionIsRejectedWithoutChangingLiveData() throws {
        let container = try makeContainer()
        let original = TenoraTask(title: "Keep me")
        container.mainContext.insert(StoredTask(task: original))
        try container.mainContext.save()
        let defaults = makeDefaults()
        let invalid = TenoraBackupPayload(
            exportedAt: Date(),
            sourceAppVersion: "test",
            sourceBuild: "test",
            tasks: [],
            habits: [],
            habitCompletions: [HabitCompletion(habitID: UUID(), completionDate: Date(), xpAwarded: 0)],
            playerProgress: [],
            gameUnlocks: [],
            transitionPlans: [],
            preferences: TenoraPreferenceBackup(defaults: defaults)
        )

        XCTAssertThrowsError(try TenoraDataArchive.restore(invalid, context: container.mainContext, defaults: defaults))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<StoredTask>()).map(\.domainModel), [original])
    }

    func testUnversionedLegacyStoreOpensWithTaskTagsIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraDataArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Tenora.store")
        let task = TenoraTask(title: "Tagged task", tags: ["home", "urgent"])

        do {
            let legacySchema = Schema([
                StoredTask.self,
                StoredHabit.self,
                StoredHabitCompletion.self,
                StoredPlayerProgress.self,
                StoredGameUnlock.self
            ])
            let configuration = ModelConfiguration("Tenora", schema: legacySchema, url: storeURL, allowsSave: true)
            let container = try ModelContainer(for: legacySchema, configurations: configuration)
            container.mainContext.insert(StoredTask(task: task))
            try container.mainContext.save()
        }

        let reopened = try TenoraModelContainerFactory.make(at: storeURL)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<StoredTask>()).map(\.domainModel), [task])
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try TenoraModelContainerFactory.makeInMemory()
        containers.append(container)
        return container
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "com.tenora.tests.\(UUID().uuidString)"
        defaultsSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
