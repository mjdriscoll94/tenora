import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class Phase2RepositoryTests: XCTestCase {
    func testSettingsAreIsolatedByProfileAndOfflineReadsLegacyValue() throws {
        let suite = "Phase2Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(11, forKey: TenoraSettingKey.legacyWorkStart.rawValue)

        let offline = UserDefaultsSettingsRepository(profileID: .offline, defaults: defaults)
        let adult = UserDefaultsSettingsRepository(profileID: LocalProfileID(rawValue: "adult-a"), defaults: defaults)

        XCTAssertEqual(offline.integer(for: .legacyWorkStart, default: 8), 11)
        XCTAssertEqual(adult.integer(for: .legacyWorkStart, default: 8), 8)
        adult.set(6, for: .legacyWorkStart)
        XCTAssertEqual(adult.integer(for: .legacyWorkStart, default: 8), 6)
        XCTAssertEqual(offline.integer(for: .legacyWorkStart, default: 8), 11)
        adult.remove(.legacyWorkStart)
        XCTAssertEqual(adult.integer(for: .legacyWorkStart, default: 8), 8)
    }

    func testStorageComponentsDoNotCollideWhenProviderSubjectsContainPunctuation() {
        XCTAssertNotEqual(
            LocalProfileID(rawValue: "provider|adult/a").storageComponent,
            LocalProfileID(rawValue: "provider|adult_a").storageComponent
        )
    }

    func testProfileRepositoryActivatesAndReturnsToOfflineProfile() throws {
        let suite = "Phase2Profiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = UserDefaultsProfileRepository(defaults: defaults)
        let profile = LocalProfileID(rawValue: "adult")

        XCTAssertEqual(repository.activeProfileID, .offline)
        repository.activate(profile)
        XCTAssertEqual(repository.activeProfileID, profile)
        repository.returnToOfflineProfile()
        XCTAssertEqual(repository.activeProfileID, .offline)
    }

    func testFileOutboxPersistsAndSeparatesProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraPhase2-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LocalProfileID(rawValue: "first")
        let second = LocalProfileID(rawValue: "second")
        let mutation = LocalMutation(profileID: first, entity: .task, recordID: "one", operation: .upsert)

        let writer = try FileMutationOutbox(directory: directory)
        try writer.enqueue(mutation)
        let reopened = try FileMutationOutbox(directory: directory)

        XCTAssertEqual(try reopened.pending(profileID: first), [mutation])
        XCTAssertTrue(try reopened.pending(profileID: second).isEmpty)
        try reopened.remove(ids: [mutation.id], profileID: first)
        XCTAssertTrue(try reopened.pending(profileID: first).isEmpty)
    }

    func testLegacyFileOutboxUpgradesToVersionedEnvelope() throws {
        struct LegacyMutation: Codable {
            let id: UUID
            let profileID: LocalProfileID
            let entity: LocalMutation.Entity
            let recordID: String
            let operation: LocalMutation.Operation
            let createdAt: Date
            let payload: Data?
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraLegacyOutbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalProfileID(rawValue: "legacy")
        let id = UUID()
        let legacy = LegacyMutation(
            id: id,
            profileID: profile,
            entity: .task,
            recordID: "task",
            operation: .upsert,
            createdAt: Date(timeIntervalSince1970: 100),
            payload: nil
        )
        let url = directory.appending(path: "\(profile.storageComponent).json")
        try JSONEncoder().encode([legacy]).write(to: url)

        let outbox = try FileMutationOutbox(directory: directory)
        let migrated = try XCTUnwrap(outbox.pending(profileID: profile).first)

        XCTAssertEqual(migrated.id, id)
        XCTAssertEqual(migrated.attemptCount, 0)
        XCTAssertEqual(migrated.state, .pending)
        XCTAssertEqual(try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8)).first, "{")
    }

    func testSwiftDataOutboxPersistsIdempotencyRetryAndBlockingState() throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        let outbox = SwiftDataMutationOutbox(modelContext: container.mainContext)
        let profile = LocalProfileID(rawValue: "retry-owner")
        let first = LocalMutation(profileID: profile, entity: .task, recordID: "one", operation: .upsert)
        let second = LocalMutation(profileID: profile, entity: .habit, recordID: "two", operation: .delete)
        let attemptedAt = Date(timeIntervalSince1970: 1_000)

        try outbox.enqueue(first)
        try outbox.enqueue(second)
        XCTAssertEqual(try outbox.ready(profileID: profile, now: attemptedAt, limit: 10).map(\.id), [first.id, second.id])

        try outbox.recordAttempt(
            ids: [first.id],
            profileID: profile,
            attemptedAt: attemptedAt,
            outcome: .retryable(failureCode: "network")
        )
        try outbox.recordAttempt(
            ids: [second.id],
            profileID: profile,
            attemptedAt: attemptedAt,
            outcome: .blocked(failureCode: "conflict")
        )

        let pending = try outbox.pending(profileID: profile)
        let retried = try XCTUnwrap(pending.first { $0.id == first.id })
        let blocked = try XCTUnwrap(pending.first { $0.id == second.id })
        XCTAssertEqual(retried.idempotencyKey, first.id.uuidString.lowercased())
        XCTAssertEqual(retried.attemptCount, 1)
        XCTAssertEqual(retried.nextAttemptAt, attemptedAt.addingTimeInterval(30))
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertTrue(try outbox.ready(profileID: profile, now: attemptedAt.addingTimeInterval(29), limit: 10).isEmpty)
        XCTAssertEqual(
            try outbox.ready(profileID: profile, now: attemptedAt.addingTimeInterval(30), limit: 10).map(\.id),
            [first.id]
        )
    }

    func testLegacyFileQueueMovesToTransactionalJournalWithoutDuplication() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraOutboxMove-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalProfileID(rawValue: "move-owner")
        let mutation = LocalMutation(profileID: profile, entity: .task, recordID: "task", operation: .upsert)
        let file = try FileMutationOutbox(directory: directory)
        try file.enqueue(mutation)
        let container = try TenoraModelContainerFactory.makeInMemory()
        let journal = SwiftDataMutationOutbox(modelContext: container.mainContext)

        XCTAssertEqual(try file.migratePending(profileID: profile, to: journal), 1)
        XCTAssertTrue(try file.pending(profileID: profile).isEmpty)
        XCTAssertEqual(try journal.pending(profileID: profile), [mutation])

        try file.enqueue(mutation)
        XCTAssertEqual(try file.migratePending(profileID: profile, to: journal), 1)
        XCTAssertEqual(try journal.pending(profileID: profile), [mutation])
    }

    func testHabitRepositoryContractPersistsRecordsAndQueuesMutations() throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraHabitOutbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalProfileID(rawValue: "habit-owner")
        let outbox = try FileMutationOutbox(directory: directory)
        let repository = SwiftDataHabitRepository(
            modelContext: container.mainContext,
            profileID: profile,
            outbox: outbox
        )
        let habit = Habit(name: "Drink water")
        let completion = HabitCompletion(habitID: habit.id, completionDate: Date(), xpAwarded: 0)

        try repository.saveHabit(habit)
        try repository.saveHabitCompletion(completion)

        XCTAssertEqual(try repository.fetchHabits(), [habit])
        XCTAssertEqual(try repository.fetchHabitCompletions(), [completion])
        var updated = habit
        updated.name = "Drink more water"
        try repository.saveHabit(updated)
        XCTAssertEqual(try repository.fetchHabits(), [updated])

        try repository.deleteHabitCompletion(id: completion.id)
        try repository.deleteHabit(id: habit.id)
        XCTAssertTrue(try repository.fetchHabitCompletions().isEmpty)
        XCTAssertTrue(try repository.fetchHabits().isEmpty)
        let mutations = try outbox.pending(profileID: profile)
        XCTAssertEqual(mutations.map(\.entity), [.habit, .habitCompletion, .habit, .habitCompletion, .habit])
        XCTAssertEqual(mutations.map(\.operation), [.upsert, .upsert, .upsert, .delete, .delete])
    }

    func testTaskRepositoryQueuesProfileScopedUpsertAndDelete() async throws {
        let container = try TenoraModelContainerFactory.makeInMemory()
        let profile = LocalProfileID(rawValue: "task-owner")
        let outbox = SwiftDataMutationOutbox(modelContext: container.mainContext)
        let repository = SwiftDataTaskRepository(
            modelContext: container.mainContext,
            profileID: profile,
            outbox: outbox
        )
        let task = TenoraTask(title: "Household planning")

        try await repository.save(task)
        try await repository.delete(id: task.id)

        let mutations = try outbox.pending(profileID: profile)
        XCTAssertEqual(mutations.map(\.entity), [.task, .task])
        XCTAssertEqual(mutations.map(\.operation), [.upsert, .delete])
        let remaining = try await repository.fetchTasks()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testTransitionRepositoryQueuesUpsertsAndDeletes() throws {
        let suite = "Phase2Transitions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraTransitionOutbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalProfileID(rawValue: "transition-owner")
        let settings = UserDefaultsSettingsRepository(profileID: profile, defaults: defaults)
        let outbox = try FileMutationOutbox(directory: directory)
        let repository = UserDefaultsTransitionRepository(settings: settings, outbox: outbox)
        let plan = TransitionPlan(eventID: "event", eventTitle: "Appointment", eventStart: Date())

        try repository.replaceTransitionPlans([plan])
        XCTAssertEqual(repository.fetchTransitionPlans(), [plan])
        try repository.replaceTransitionPlans([])

        XCTAssertEqual(try outbox.pending(profileID: profile).map(\.operation), [.upsert, .delete])
    }

    func testWidgetReadsOnlyTheActiveProfilesSnapshot() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: WidgetSnapshot.groupID))
        let first = "widget-first-\(UUID().uuidString)"
        let second = "widget-second-\(UUID().uuidString)"
        defer {
            defaults.removeObject(forKey: WidgetSnapshot.storageKey(profileID: first))
            defaults.removeObject(forKey: WidgetSnapshot.storageKey(profileID: second))
            defaults.removeObject(forKey: WidgetSnapshot.activeProfileKey)
        }
        let firstTask = TenoraTask(title: "Private first task")
        let secondTask = TenoraTask(title: "Second task")
        let firstSnapshot = WidgetSnapshot(
            updatedAt: Date(), tasks: [firstTask], events: [], calendarKnown: false,
            startHour: 8, endHour: 18, focusedTaskID: firstTask.id
        )
        let secondSnapshot = WidgetSnapshot(
            updatedAt: Date(), tasks: [secondTask], events: [], calendarKnown: false,
            startHour: 8, endHour: 18, focusedTaskID: nil
        )
        defaults.set(try JSONEncoder().encode(firstSnapshot), forKey: WidgetSnapshot.storageKey(profileID: first))
        defaults.set(try JSONEncoder().encode(secondSnapshot), forKey: WidgetSnapshot.storageKey(profileID: second))

        defaults.set(second, forKey: WidgetSnapshot.activeProfileKey)
        let active = try XCTUnwrap(WidgetSnapshot.read())

        XCTAssertEqual(active.tasks.map(\.title), ["Second task"])
        XCTAssertNil(active.focusedTaskID)
    }
}
