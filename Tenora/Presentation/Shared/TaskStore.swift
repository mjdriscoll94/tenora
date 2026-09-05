import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TenoraTask] = []
    @Published private(set) var errorMessage: String?

    private let repository: any TaskRepository
    private let clock: any TenoraClock
    private let priorityEngine: TaskPriorityEngine
    private let resurfacingEngine: ResurfacingEngine
    private let calendar: Calendar
    var didChange: (([TenoraTask]) async -> Void)?

    init(
        repository: any TaskRepository,
        clock: any TenoraClock = SystemClock(),
        priorityEngine: TaskPriorityEngine = TaskPriorityEngine(),
        resurfacingEngine: ResurfacingEngine = ResurfacingEngine(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.clock = clock
        self.priorityEngine = priorityEngine
        self.resurfacingEngine = resurfacingEngine
        self.calendar = calendar
    }

    var inboxTasks: [TenoraTask] {
        tasks.filter { ![.completed, .archived].contains($0.status) }
    }

    var nowRecommendation: TenoraTask? {
        recommendation(availableMinutes: nil)
    }

    func recommendation(availableMinutes: Int?) -> TenoraTask? {
        priorityEngine.recommendation(
            from: tasks,
            context: .init(
                now: clock.now,
                availableMinutes: availableMinutes,
                calendar: calendar
            )
        )
    }

    var resurfacedTasks: [TenoraTask] {
        resurfacingEngine.tasksToSurface(from: tasks, at: clock.now)
    }

    func load() async {
        do {
            tasks = try await repository.fetchTasks()
            errorMessage = nil
            await didChange?(tasks)
        } catch {
            errorMessage = "Tenora couldn't load your tasks."
        }
    }

    func createTask(
        title: String,
        notes: String = "",
        estimatedDurationMinutes: Int? = nil
    ) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }

        do {
            var task = TenoraTask(title: cleanTitle, notes: notes, createdAt: clock.now)
            task.estimatedDurationMinutes = estimatedDurationMinutes
            task.nextSurfaceAt = resurfacingEngine.initialSurfaceDate(for: task, calendar: calendar)
            try await repository.save(task)
            tasks = try await repository.fetchTasks()
            errorMessage = nil
            await didChange?(tasks)
            return true
        } catch {
            errorMessage = "Tenora couldn't save that task."
            return false
        }
    }

    @discardableResult
    func complete(_ task: TenoraTask) async -> Bool {
        guard var completedTask = tasks.first(where: { $0.id == task.id }) else { return false }
        completedTask.complete(at: clock.now)
        return await saveAndReload(completedTask, failureMessage: "Tenora couldn't complete that task.")
    }

    func postpone(_ task: TenoraTask) async {
        let postponedTask = resurfacingEngine.postpone(task, at: clock.now, calendar: calendar)
        await saveAndReload(postponedTask, failureMessage: "Tenora couldn't bring that task back later.")
    }

    func notificationAction(id: UUID, action: String) async -> Bool {
        do { tasks = try await repository.fetchTasks() } catch { return false }
        guard var task = tasks.first(where: { $0.id == id }) else { return true }
        guard ![.completed, .archived].contains(task.status) else { return true }
        switch action {
        case "DONE": task.complete(at: clock.now)
        case "LATER": task = resurfacingEngine.postpone(task, at: clock.now, calendar: calendar)
        case "TOMORROW":
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock.now)!
            task.scheduledDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            task.nextSurfaceAt = task.scheduledDate
            task.status = .scheduled
        default: return false
        }
        return await saveAndReload(task, failureMessage: "Your reminder decision couldn't be saved.")
    }

    func update(_ draft: TenoraTask) async -> Bool {
        guard let previous = tasks.first(where: { $0.id == draft.id }) else { return false }
        do {
            let task = try TaskEditor.validated(draft, previous: previous, now: clock.now)
            return await saveAndReload(task, failureMessage: "Tenora couldn't save your changes.")
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func delete(_ id: UUID) async -> Bool {
        do {
            try await repository.delete(id: id)
            await load()
            return errorMessage == nil
        } catch { errorMessage = "Tenora couldn't delete that task."; return false }
    }

    @discardableResult
    private func saveAndReload(_ task: TenoraTask, failureMessage: String) async -> Bool {
        do {
            try await repository.save(task)
            tasks = try await repository.fetchTasks()
            errorMessage = nil
            await didChange?(tasks)
            return true
        } catch {
            errorMessage = failureMessage
            return false
        }
    }
}
