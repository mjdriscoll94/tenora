import SwiftData

/// One container and repository shared by the application and its foreground intents.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let container: ModelContainer
    let tasks: TaskStore
    let calendar: CalendarStore

    private init() {
        do {
            container = try ModelContainer(for: StoredTask.self)
            tasks = TaskStore(repository: SwiftDataTaskRepository(modelContext: container.mainContext))
            calendar = CalendarStore(repository: EventKitCalendarRepository())
            tasks.didChange = { [weak self] tasks in
                self?.publishWidget()
                await ReminderService.shared.synchronize(tasks: tasks)
            }
            calendar.didChange = { [weak self] in self?.publishWidget() }
            ReminderService.shared.handleAction = { [weak tasks] id, action in
                await tasks?.notificationAction(id: id, action: action) ?? false
            }
        } catch { fatalError("Unable to initialize Tenora's local store: \(error)") }
    }

    func publishWidget() {
        WidgetPublisher.publish(tasks: tasks.tasks, events: calendar.events,
            calendarKnown: calendar.availability != nil)
    }
}
