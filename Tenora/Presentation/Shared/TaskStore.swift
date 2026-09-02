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
        tasks.filter { $0.status == .inbox }
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
            return true
        } catch {
            errorMessage = "Tenora couldn't save that task."
            return false
        }
    }

    func complete(_ task: TenoraTask) async {
        var completedTask = task
        completedTask.complete(at: clock.now)
        await saveAndReload(completedTask, failureMessage: "Tenora couldn't complete that task.")
    }

    func postpone(_ task: TenoraTask) async {
        let postponedTask = resurfacingEngine.postpone(task, at: clock.now, calendar: calendar)
        await saveAndReload(postponedTask, failureMessage: "Tenora couldn't bring that task back later.")
    }

    private func saveAndReload(_ task: TenoraTask, failureMessage: String) async {
        do {
            try await repository.save(task)
            tasks = try await repository.fetchTasks()
            errorMessage = nil
        } catch {
            errorMessage = failureMessage
        }
    }
}
