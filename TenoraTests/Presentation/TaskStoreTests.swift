import XCTest
@testable import Tenora

@MainActor
final class TaskStoreTests: XCTestCase {
    func testJustStartPersistsAndDoneForNowReturnsWithoutPenalty() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let task = TenoraTask(title: "Taxes", dueDate: now.addingTimeInterval(86_400))
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository, clock: FixedClock(now: now))
        await store.load()
        let began = await store.beginJustStart(task.id, nextStep: "  Find the folder  ", durationSeconds: 180)
        XCTAssertTrue(began)
        XCTAssertEqual(store.activeJustStartTask?.nextStep, "Find the folder")
        XCTAssertEqual(store.activeJustStartTask?.justStartEndsAt, now.addingTimeInterval(180))

        let reopened = TaskStore(repository: repository, clock: FixedClock(now: now.addingTimeInterval(200)))
        await reopened.load()
        XCTAssertEqual(reopened.activeJustStartTask?.id, task.id)
        let stopped = await reopened.finishJustStart(task.id, keepGoing: false)
        XCTAssertTrue(stopped)
        XCTAssertNil(reopened.focusedTaskID)
        XCTAssertNil(reopened.tasks.first?.justStartEndsAt)
        XCTAssertEqual(reopened.tasks.first?.status, .inbox)
        XCTAssertEqual(reopened.tasks.first?.snoozeCount, 0)
        XCTAssertEqual(reopened.tasks.first?.nextSurfaceAt, now.addingTimeInterval(200 + 4 * 3600))
        XCTAssertEqual(reopened.tasks.first?.dueDate, task.dueDate)
    }

    func testKeepGoingRemovesTimerAndKeepsFocus() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let now = Date()
        let task = TenoraTask(title: "Draft")
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository, clock: FixedClock(now: now))
        await store.load()
        let began = await store.beginJustStart(task.id, nextStep: "Open the draft", durationSeconds: 1)
        XCTAssertTrue(began)
        let continued = await store.finishJustStart(task.id, keepGoing: true)
        XCTAssertTrue(continued)
        XCTAssertEqual(store.currentTask?.id, task.id)
        XCTAssertEqual(store.currentTask?.status, .active)
        XCTAssertNil(store.currentTask?.justStartEndsAt)
    }

    func testJustStartNotificationActionsUseTheSameSessionDecisions() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let task = TenoraTask(title: "Start", nextStep: "Open it", justStartBeganAt: Date(), justStartDurationSeconds: 180)
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository)
        let keptGoing = await store.notificationAction(id: task.id, action: "KEEP_GOING")
        XCTAssertTrue(keptGoing)
        XCTAssertEqual(store.currentTask?.id, task.id)
        XCTAssertNil(store.currentTask?.justStartEndsAt)

        let second = TenoraTask(title: "Stop", nextStep: "One line", justStartBeganAt: Date(), justStartDurationSeconds: 180)
        repository.tasks = [second]
        let stopped = await store.notificationAction(id: second.id, action: "DONE_FOR_NOW")
        XCTAssertTrue(stopped)
        XCTAssertNil(store.focusedTaskID)
        XCTAssertEqual(store.tasks.first?.status, .inbox)
        XCTAssertEqual(store.tasks.first?.snoozeCount, 0)
    }

    func testInvalidOrFailedJustStartDoesNotReplaceFocus() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let first = TenoraTask(title: "Current")
        let second = TenoraTask(title: "Next")
        let repository = MemoryTasks(tasks: [first, second])
        let store = TaskStore(repository: repository)
        await store.load()
        await store.start(first)
        let invalid = await store.beginJustStart(second.id, nextStep: "  ", durationSeconds: 180)
        XCTAssertFalse(invalid)
        repository.failSave = true
        let failed = await store.beginJustStart(second.id, nextStep: "Open it", durationSeconds: 180)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.focusedTaskID, first.id)
        XCTAssertNil(repository.tasks.first(where: { $0.id == second.id })?.justStartEndsAt)
    }

    func testHoldSurvivesReloadAndResumeClearsReturnTime() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let task = TenoraTask(title: "Slides", dueDate: Date())
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository)
        await store.load()
        await store.start(task)
        let returnAt = Date().addingTimeInterval(3600)
        let held = await store.hold(task.id, nextStep: "  Find image  ", reason: "Meeting", returnAt: returnAt)
        XCTAssertTrue(held)
        XCTAssertNil(store.focusedTaskID)
        let reopened = TaskStore(repository: repository)
        await reopened.load()
        let resume = try! XCTUnwrap(reopened.resumeTask)
        XCTAssertEqual(resume.nextStep, "Find image")
        XCTAssertEqual(resume.holdReason, "Meeting")
        XCTAssertEqual(resume.nextSurfaceAt, returnAt)
        await reopened.start(resume)
        XCTAssertEqual(reopened.currentTask?.id, task.id)
        XCTAssertNil(reopened.currentTask?.scheduledDate)
        XCTAssertNil(reopened.currentTask?.nextSurfaceAt)
        XCTAssertEqual(reopened.currentTask?.dueDate, task.dueDate)
        await reopened.complete(resume)
        XCTAssertNil(reopened.resumeTask)
    }

    func testFailedHoldRetainsCurrentTask() async {
        let previous = UserDefaults.standard.string(forKey: "focusedTask")
        defer { UserDefaults.standard.set(previous, forKey: "focusedTask") }
        let task = TenoraTask(title: "Focus")
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository)
        await store.load()
        await store.start(task)
        repository.failSave = true
        let held = await store.hold(task.id, nextStep: "Next", reason: "", returnAt: nil)
        XCTAssertFalse(held)
        XCTAssertEqual(store.currentTask?.id, task.id)
        XCTAssertNil(store.currentTask?.heldAt)
    }
    func testStartPinsAndLaterReleasesPersistedTask() async {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "focusedTask")
        defer { defaults.set(previous, forKey: "focusedTask") }
        let now = Date()
        let task = TenoraTask(title: "Focus", createdAt: now)
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository)
        await store.load()
        await store.start(task)
        XCTAssertEqual(store.focusedTaskID, task.id)
        XCTAssertEqual(repository.tasks.first?.status, .active)
        await store.postpone(task)
        XCTAssertNil(store.focusedTaskID)
        XCTAssertEqual(repository.tasks.first?.snoozeCount, 1)
        XCTAssertGreaterThan(repository.tasks.first!.nextSurfaceAt!, now)
    }

    func testNotificationCompletionPersistsAndCannotBeReopenedByLater() async {
        let task = TenoraTask(title: "Done", createdAt: Date())
        let repository = MemoryTasks(tasks: [task])
        let store = TaskStore(repository: repository)
        let done = await store.notificationAction(id: task.id, action: "DONE")
        XCTAssertTrue(done)
        let later = await store.notificationAction(id: task.id, action: "LATER")
        XCTAssertTrue(later)
        XCTAssertEqual(repository.tasks.first?.status, .completed)
        XCTAssertNil(repository.tasks.first?.nextSurfaceAt)
    }

    func testFailedStartDoesNotKeepFocus() async {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "focusedTask")
        defaults.removeObject(forKey: "focusedTask")
        defer { defaults.set(previous, forKey: "focusedTask") }
        let task = TenoraTask(title: "Retry", createdAt: Date())
        let repository = MemoryTasks(tasks: [task])
        repository.failSave = true
        let store = TaskStore(repository: repository)
        await store.load()
        await store.start(task)
        XCTAssertNil(store.focusedTaskID)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(repository.tasks.first?.status, .inbox)
    }
}

@MainActor
private final class MemoryTasks: TaskRepository {
    var tasks: [TenoraTask]
    var failSave = false
    init(tasks: [TenoraTask]) { self.tasks = tasks }
    func fetchTasks() async throws -> [TenoraTask] { tasks }
    func save(_ task: TenoraTask) async throws {
        if failSave { throw NSError(domain: "Test", code: 1) }
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
    }
    func delete(id: UUID) async throws { tasks.removeAll { $0.id == id } }
}

private struct FixedClock: TenoraClock {
    let now: Date
}
