import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TenoraTask] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var focusedTaskID: UUID?

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
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.clock = clock
        self.priorityEngine = priorityEngine
        self.resurfacingEngine = resurfacingEngine
        self.calendar = calendar
        focusedTaskID = UserDefaults.standard.string(forKey: "focusedTask").flatMap(UUID.init(uuidString:))
    }

    var inboxTasks: [TenoraTask] {
        tasks.filter { ![.completed, .archived].contains($0.status) }
    }

    var nowRecommendation: TenoraTask? {
        recommendation(availableMinutes: nil)
    }

    func recommendation(availableMinutes: Int?) -> TenoraTask? {
        let context = priorityContext(availableMinutes)
        if let focus = tasks.first(where: { $0.id == focusedTaskID }), priorityEngine.isEligible(focus, context: context) { return focus }
        return priorityEngine.recommendation(from: tasks, context: context)
    }

    private func priorityContext(_ availableMinutes: Int?) -> TaskPriorityEngine.Context {
        .init(now: clock.now, availableMinutes: availableMinutes, calendar: calendar, schedule: AttentionPreferences.schedule)
    }

    func reason(for task: TenoraTask, availableMinutes: Int?) -> String {
        if task.id == focusedTaskID { return "You're working on this. Tenora is holding your place." }
        return priorityEngine.reason(for: task, context: priorityContext(availableMinutes))
    }

    @discardableResult
    func start(_ task: TenoraTask) async -> Bool {
        guard var current = tasks.first(where: { $0.id == task.id }), ![.completed, .archived].contains(current.status) else { return false }
        current.status = .active
        current.lastWorkedAt = clock.now
        current.scheduledDate = nil
        current.nextSurfaceAt = nil
        current.returnTrigger = nil
        current.snoozeCount = 0
        current.lastSurfacedAt = clock.now
        current.surfaceCount += 1
        let previousFocus = focusedTaskID
        setFocus(current.id)
        if !(await saveAndReload(current, failureMessage: "Tenora couldn't start this task.")) { setFocus(previousFocus); return false }
        return true
    }

    var currentTask: TenoraTask? {
        tasks.first { $0.id == focusedTaskID && ![.completed, .archived].contains($0.status) }
    }

    var activeJustStartTask: TenoraTask? {
        guard let currentTask, currentTask.justStartEndsAt != nil else { return nil }
        return currentTask
    }

    func beginJustStart(_ id: UUID, nextStep: String, durationSeconds: Int) async -> Bool {
        let cleanStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanStep.isEmpty, (1...3600).contains(durationSeconds),
              var task = tasks.first(where: { $0.id == id }), ![.completed, .archived].contains(task.status) else { return false }
        task.nextStep = cleanStep
        task.justStartBeganAt = clock.now
        task.justStartDurationSeconds = durationSeconds
        task.status = .active
        task.lastWorkedAt = clock.now
        task.scheduledDate = nil
        task.nextSurfaceAt = nil
        task.snoozeCount = 0
        let previousFocus = focusedTaskID
        setFocus(id)
        if !(await saveAndReload(task, failureMessage: "Tenora couldn't start this short session.")) {
            setFocus(previousFocus)
            return false
        }
        return true
    }

    func finishJustStart(_ id: UUID, keepGoing: Bool) async -> Bool {
        guard var task = tasks.first(where: { $0.id == id }), task.justStartEndsAt != nil,
              ![.completed, .archived].contains(task.status) else { return false }
        task.clearJustStart()
        task.lastWorkedAt = clock.now
        let previousFocus = focusedTaskID
        if keepGoing {
            task.status = .active
            setFocus(id)
        } else {
            task.status = .inbox
            task.heldAt = clock.now
            task.holdReason = "Finished a short start"
            task.nextSurfaceAt = clock.now.addingTimeInterval(4 * 3600)
            task.snoozeCount = 0
            setFocus(nil)
        }
        if !(await saveAndReload(task, failureMessage: "Tenora couldn't save the end of this session.")) {
            setFocus(previousFocus)
            return false
        }
        return true
    }

    var resumeTask: TenoraTask? {
        if let currentTask { return currentTask }
        return inboxTasks.filter { $0.lastWorkedAt != nil || $0.heldAt != nil }
            .max { max($0.lastWorkedAt ?? .distantPast, $0.heldAt ?? .distantPast) < max($1.lastWorkedAt ?? .distantPast, $1.heldAt ?? .distantPast) }
    }

    func hold(_ id: UUID, nextStep: String, reason: String, returnAt: Date?) async -> Bool {
        guard var task = tasks.first(where: { $0.id == id }), ![.completed, .archived].contains(task.status) else { return false }
        task.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        task.holdReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        task.heldAt = clock.now
        task.scheduledDate = returnAt
        task.nextSurfaceAt = returnAt ?? clock.now.addingTimeInterval(4 * 3600)
        task.snoozeCount = max(1, task.snoozeCount)
        task.status = returnAt == nil ? .inbox : .scheduled
        task.returnTrigger = nil
        task.clearJustStart()
        return await saveAndReload(task, failureMessage: "Tenora couldn't hold your place. Please try again.")
    }

    private func setFocus(_ id: UUID?) {
        focusedTaskID = id
        UserDefaults.standard.set(id?.uuidString, forKey: "focusedTask")
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
        estimatedDurationMinutes: Int? = nil,
        source: TaskSource = .manual
    ) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }

        do {
            var task = TenoraTask(title: cleanTitle, notes: notes, createdAt: clock.now)
            task.estimatedDurationMinutes = estimatedDurationMinutes
            task.source = source
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

    func setReturnTrigger(_ trigger: ReturnTrigger?, for id: UUID, availability: AvailabilitySnapshot? = nil) async -> Bool {
        guard var task = tasks.first(where: { $0.id == id }), ![.completed, .archived].contains(task.status) else { return false }
        task.returnTrigger = trigger
        task.clearJustStart()
        if let trigger {
            let engine = ReturnTriggerEngine()
            if engine.isReady(trigger, tasks: tasks, events: [], availability: availability, now: clock.now) {
                task.returnTrigger = nil
                task.nextSurfaceAt = clock.now
                task.scheduledDate = nil
                task.status = .inbox
            } else {
                let candidate = engine.nextCandidate(for: trigger, availability: availability, now: clock.now)
                task.nextSurfaceAt = candidate
                task.scheduledDate = candidate
                task.status = candidate == nil ? .waiting : .scheduled
            }
        } else {
            task.nextSurfaceAt = nil
            task.scheduledDate = nil
            task.status = .inbox
        }
        return await saveAndReload(task, failureMessage: "Tenora couldn't save that return condition.")
    }

    func resolveReturnTriggers(events: [CalendarEvent], availability: AvailabilitySnapshot?) async {
        let engine = ReturnTriggerEngine()
        let snapshot = tasks
        for var task in snapshot where task.returnTrigger != nil && ![.completed, .archived].contains(task.status) {
            guard let trigger = task.returnTrigger else { continue }
            if engine.isReady(trigger, tasks: snapshot, events: events, availability: availability, now: clock.now) {
                task.returnTrigger = nil
                task.status = .inbox
                task.scheduledDate = nil
                task.nextSurfaceAt = clock.now
                _ = await saveAndReload(task, failureMessage: "Tenora couldn't bring a task back yet.")
            } else if let candidate = engine.nextCandidate(for: trigger, availability: availability, now: clock.now), candidate != task.nextSurfaceAt {
                task.nextSurfaceAt = candidate
                task.scheduledDate = candidate
                task.status = .scheduled
                _ = await saveAndReload(task, failureMessage: "Tenora couldn't update a return time.")
            }
        }
    }

    func postpone(_ task: TenoraTask) async {
        guard var current = tasks.first(where: { $0.id == task.id }), ![.completed, .archived].contains(current.status) else { return }
        current.clearJustStart()
        let postponedTask = resurfacingEngine.postpone(current, at: clock.now, calendar: calendar)
        await saveAndReload(postponedTask, failureMessage: "Tenora couldn't bring that task back later.")
    }

    func notificationAction(id: UUID, action: String) async -> Bool {
        do { tasks = try await repository.fetchTasks() } catch { return false }
        guard var task = tasks.first(where: { $0.id == id }) else { return true }
        guard ![.completed, .archived].contains(task.status) else { return true }
        switch action {
        case "KEEP_GOING": return await finishJustStart(id, keepGoing: true)
        case "DONE_FOR_NOW": return await finishJustStart(id, keepGoing: false)
        case "DONE": task.complete(at: clock.now)
        case "LATER": task.clearJustStart(); task = resurfacingEngine.postpone(task, at: clock.now, calendar: calendar)
        case "TOMORROW":
            task.clearJustStart()
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock.now)!
            task.scheduledDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            task.nextSurfaceAt = task.scheduledDate
            task.status = .scheduled
        default: return false
        }
        return await saveAndReload(task, failureMessage: "Your reminder decision couldn't be saved.")
    }

    var reviewTasks: [TenoraTask] { ReviewEngine().queue(tasks: tasks, now: clock.now, calendar: calendar) }

    func review(_ id: UUID, decision: ReviewDecision) async -> Bool {
        guard let task = tasks.first(where: { $0.id == id }) else { return false }
        let updated = ReviewEngine().apply(decision, to: task, now: clock.now, calendar: calendar)
        return await saveAndReload(updated, failureMessage: "That decision couldn't be saved. Please try again.")
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
            if focusedTaskID == id { setFocus(nil) }
            await load()
            return errorMessage == nil
        } catch { errorMessage = "Tenora couldn't delete that task."; return false }
    }

    @discardableResult
    private func saveAndReload(_ task: TenoraTask, failureMessage: String) async -> Bool {
        do {
            try await repository.save(task)
            if task.id == focusedTaskID && ([.completed, .archived, .scheduled].contains(task.status) || (task.nextSurfaceAt ?? .distantPast) > clock.now && task.snoozeCount > 0) { setFocus(nil) }
            tasks = try await repository.fetchTasks()
            errorMessage = nil
            await didChange?(tasks)
            if task.status == .completed { await resolveReturnTriggers(events: [], availability: nil) }
            return true
        } catch {
            errorMessage = failureMessage
            return false
        }
    }
}
