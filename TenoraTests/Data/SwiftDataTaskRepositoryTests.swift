import SwiftData
import XCTest
@testable import Tenora

@MainActor
final class SwiftDataTaskRepositoryTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeRepository() throws -> SwiftDataTaskRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: StoredTask.self,
            configurations: configuration
        )
        containers.append(container)
        return SwiftDataTaskRepository(modelContext: container.mainContext)
    }

    func testSaveAndFetchTask() async throws {
        let repository = try makeRepository()
        let task = TenoraTask(title: "Call insurance", notes: "Ask about coverage")

        try await repository.save(task)
        let fetched = try await repository.fetchTasks()

        XCTAssertEqual(fetched, [task])
    }

    func testSavedContextSurvivesFetchAndEditing() async throws {
        let repository = try makeRepository()
        var task = TenoraTask(title: "Slides", nextStep: "Find slide seven image", heldAt: Date(), holdReason: "Meeting", lastWorkedAt: Date())
        try await repository.save(task)
        var fetched = try await repository.fetchTasks()
        XCTAssertEqual(fetched, [task])
        task.nextStep = "Add the caption"
        try await repository.save(task)
        fetched = try await repository.fetchTasks()
        XCTAssertEqual(fetched, [task])
    }

    func testOldSnapshotWithoutContextStillDecodes() throws {
        let task = TenoraTask(title: "Existing task")
        let data = try JSONEncoder().encode(task)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["nextStep", "heldAt", "holdReason", "lastWorkedAt"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(TenoraTask.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, task)
    }

    func testSavingExistingTaskUpdatesInsteadOfDuplicating() async throws {
        let repository = try makeRepository()
        var task = TenoraTask(title: "Draft email")
        try await repository.save(task)

        task.complete(at: Date(timeIntervalSince1970: 1_700_000_000))
        try await repository.save(task)
        let fetched = try await repository.fetchTasks()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.status, .completed)
        XCTAssertNotNil(fetched.first?.completedAt)
    }

    func testDeleteRemovesTask() async throws {
        let repository = try makeRepository()
        let task = TenoraTask(title: "Temporary task")
        try await repository.save(task)

        try await repository.delete(id: task.id)

        let fetched = try await repository.fetchTasks()
        XCTAssertTrue(fetched.isEmpty)
    }
}
