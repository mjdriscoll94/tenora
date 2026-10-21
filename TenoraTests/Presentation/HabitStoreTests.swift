import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class HabitStoreTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeStore() throws -> (ModelContainer, HabitStore) {
        let container = try ModelContainer(
            for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return (container, HabitStore(modelContext: container.mainContext))
    }

    func testHabitAndCheckInPersistAcrossStoreReload() async throws {
        let (container, store) = try makeStore()
        let habit = Habit(name: "Read", difficulty: .standard)
        let saved = await store.save(habit)
        let completed = await store.toggleCompletion(habit)
        XCTAssertTrue(saved)
        XCTAssertTrue(completed)
        XCTAssertEqual(store.progress.totalCompletions, 1)

        let reopened = HabitStore(modelContext: container.mainContext)
        await reopened.load()
        XCTAssertEqual(reopened.habits.map(\.name), ["Read"])
        XCTAssertEqual(reopened.completions.count, 1)
        XCTAssertEqual(reopened.progress.totalCompletions, 1)
        XCTAssertTrue(reopened.isCompleted(habit))
    }

    func testUndoCompletionRecalculatesTrackingSummary() async throws {
        let (_, store) = try makeStore()
        let habit = Habit(name: "Walk", difficulty: .easy)
        let saved = await store.save(habit)
        let completed = await store.toggleCompletion(habit)
        XCTAssertTrue(saved)
        XCTAssertTrue(completed)
        let undone = await store.toggleCompletion(habit)
        XCTAssertTrue(undone)
        XCTAssertEqual(store.progress.totalCompletions, 0)
        XCTAssertFalse(store.isCompleted(habit))
    }

    func testPreviousDayCheckInIsStoredOnSelectedDate() async throws {
        let (container, store) = try makeStore()
        let calendar = Calendar.autoupdatingCurrent
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date()))
        let createdAt = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: Date()))
        let habit = Habit(name: "Stretch", createdAt: createdAt)

        let saved = await store.save(habit)
        let checkedIn = await store.toggleCompletion(habit, on: yesterday)
        XCTAssertTrue(saved)
        XCTAssertTrue(checkedIn)
        XCTAssertTrue(store.isCompleted(habit, on: yesterday))
        XCTAssertFalse(store.isCompleted(habit))

        let reopened = HabitStore(modelContext: container.mainContext)
        await reopened.load()
        XCTAssertTrue(reopened.isCompleted(habit, on: yesterday))
        XCTAssertFalse(reopened.isCompleted(habit))
    }

    func testLoadingPracticalTrackerPreservesRetiredGameProgress() async throws {
        let (container, store) = try makeStore()
        let legacy = PlayerProgress(
            totalXP: 3_200,
            level: 24,
            xpIntoLevel: 80,
            xpForNextLevel: 250,
            totalCompletions: 99,
            currentMomentum: 12,
            longestMomentum: 20,
            perfectDays: 30
        )
        container.mainContext.insert(StoredPlayerProgress(progress: legacy))
        try container.mainContext.save()

        await store.load()

        XCTAssertEqual(store.progress.totalXP, legacy.totalXP)
        XCTAssertEqual(store.progress.level, legacy.level)
        XCTAssertEqual(store.progress.xpIntoLevel, legacy.xpIntoLevel)
        XCTAssertEqual(store.progress.xpForNextLevel, legacy.xpForNextLevel)
        let persisted = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<StoredPlayerProgress>()).first)
        XCTAssertEqual(persisted.totalXP, legacy.totalXP)
        XCTAssertEqual(persisted.level, legacy.level)
    }
}
