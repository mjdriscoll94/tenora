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

    func testHabitAndProgressPersistAcrossStoreReload() async throws {
        let (container, store) = try makeStore()
        let habit = Habit(name: "Read", difficulty: .standard)
        let saved = await store.save(habit)
        let completed = await store.toggleCompletion(habit)
        XCTAssertTrue(saved)
        XCTAssertTrue(completed)
        XCTAssertEqual(store.progress.totalXP, 20)

        let reopened = HabitStore(modelContext: container.mainContext)
        await reopened.load()
        XCTAssertEqual(reopened.habits.map(\.name), ["Read"])
        XCTAssertEqual(reopened.completions.count, 1)
        XCTAssertEqual(reopened.progress.totalXP, 20)
        XCTAssertTrue(reopened.achievementIDs.contains("first-step"))
    }

    func testUndoCompletionRecalculatesButKeepsEarnedUnlock() async throws {
        let (_, store) = try makeStore()
        let habit = Habit(name: "Walk", difficulty: .easy)
        let saved = await store.save(habit)
        let completed = await store.toggleCompletion(habit)
        XCTAssertTrue(saved)
        XCTAssertTrue(completed)
        XCTAssertTrue(store.achievementIDs.contains("first-step"))
        let undone = await store.toggleCompletion(habit)
        XCTAssertTrue(undone)
        XCTAssertEqual(store.progress.totalXP, 0)
        XCTAssertEqual(store.progress.totalCompletions, 0)
        XCTAssertTrue(store.achievementIDs.contains("first-step"), "Earned rewards never disappear")
    }
}
