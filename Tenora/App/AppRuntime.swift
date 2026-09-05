import Foundation
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
            #if DEBUG
            let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            #else
            let uiTesting = false
            #endif
            if uiTesting {
                container = try ModelContainer(for: StoredTask.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } else {
                container = try ModelContainer(for: StoredTask.self)
            }
            tasks = TaskStore(repository: SwiftDataTaskRepository(modelContext: container.mainContext))
            let calendarRepository = EventKitCalendarRepository()
            calendar = CalendarStore(repository: calendarRepository)
            if uiTesting { return }
            calendarRepository.onChange = { [weak calendar] in Task { await calendar?.refresh() } }
            tasks.didChange = { [weak self] tasks in
                self?.publishWidget()
                await ReminderService.shared.synchronize(tasks: tasks.filter { $0.id != self?.tasks.focusedTaskID })
            }
            calendar.didChange = { [weak self] in self?.publishWidget() }
            ReminderService.shared.handleAction = { [weak tasks] id, action in
                await tasks?.notificationAction(id: id, action: action) ?? false
            }
        } catch { fatalError("Unable to initialize Tenora's local store: \(error)") }
    }

    func publishWidget() {
        WidgetPublisher.publish(tasks: tasks.tasks, events: calendar.events,
            calendarKnown: calendar.availability != nil, focusedTaskID: tasks.focusedTaskID)
    }
}
