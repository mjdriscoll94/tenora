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
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TenoraTaskOutbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalProfileID(rawValue: "task-owner")
        let outbox = try FileMutationOutbox(directory: directory)
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
