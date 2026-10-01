import Foundation
import SwiftData

/// One container and repository shared by the application and its foreground intents.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let container: ModelContainer
    let tasks: TaskStore
    let calendar: CalendarStore
    let transitions: TransitionStore
    let habits: HabitStore

    private init() {
        do {
            #if DEBUG
            let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
            if ProcessInfo.processInfo.arguments.contains("-reset-working-schedule") {
                UserDefaults.standard.removeObject(forKey: AttentionPreferences.scheduleKey)
            }
            if uiTesting {
                container = try ModelContainer(
                    for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } else {
                container = try ModelContainer(for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self)
            }
            #else
            container = try ModelContainer(for: StoredTask.self, StoredHabit.self, StoredHabitCompletion.self, StoredPlayerProgress.self, StoredGameUnlock.self)
            #endif
            tasks = TaskStore(repository: SwiftDataTaskRepository(modelContext: container.mainContext))
            habits = HabitStore(modelContext: container.mainContext)
            let calendarRepository = EventKitCalendarRepository()
            calendar = CalendarStore(repository: calendarRepository)
            transitions = TransitionStore()
            #if DEBUG
            if uiTesting {
                if ProcessInfo.processInfo.arguments.contains("-continuity-fixture") {
                    var allDaySchedule = WorkingSchedule()
                    for index in allDaySchedule.days.indices {
                        allDaySchedule.days[index].startMinute = 0
                        allDaySchedule.days[index].endMinute = 0
                    }
                    if let data = try? JSONEncoder().encode(allDaySchedule),
                       let json = String(data: data, encoding: .utf8) {
                        UserDefaults.standard.set(json, forKey: AttentionPreferences.scheduleKey)
                    }
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                    let task = TenoraTask(
                        title: "Finish lesson notes",
                        nextStep: "Write the opening paragraph",
                        heldAt: Date(),
                        holdReason: "Lunch",
                        keepInFrontUntil: tomorrow
                    )
                    container.mainContext.insert(StoredTask(task: task))
                    try container.mainContext.save()
                }
                if ProcessInfo.processInfo.arguments.contains("-swipe-fixture") {
                    container.mainContext.insert(StoredTask(task: TenoraTask(title: "Swipe action task")))
                    try container.mainContext.save()
                }
                return
            }
            #endif
            calendarRepository.onChange = { [weak calendar] in Task { await calendar?.refresh() } }
            tasks.didChange = { [weak self] tasks in
                self?.publishWidget()
                await ReminderService.shared.synchronizeJustStart(tasks: tasks)
                await ReminderService.shared.synchronize(tasks: tasks.filter { $0.id != self?.tasks.focusedTaskID })
                if TenoraFeatures.agentBridgeEnabled {
                    AgentBridgeSyncService.shared.enqueue(tasks: tasks, events: self?.calendar.events ?? [], focusedTaskID: self?.tasks.focusedTaskID)
                }
            }
            transitions.didChange = { plans in await ReminderService.shared.synchronizeTransitions(plans: plans) }
            habits.didChange = { [weak self] in
                guard let self else { return }
                self.publishWidget()
                await ReminderService.shared.synchronizeHabits(habits: self.habits.activeHabits, completions: self.habits.completions)
            }
            calendar.didChange = { [weak self] in
                guard let self else { return }
                Task {
                    await self.tasks.resolveReturnTriggers(events: self.calendar.events, availability: self.calendar.availability)
                    await self.transitions.synchronize(events: self.calendar.events)
                    self.publishWidget()
                    if TenoraFeatures.agentBridgeEnabled {
                        AgentBridgeSyncService.shared.enqueue(tasks: self.tasks.tasks, events: self.calendar.events, focusedTaskID: self.tasks.focusedTaskID)
                    }
                }
            }
            ReminderService.shared.handleAction = { [weak tasks] id, action in
                await tasks?.notificationAction(id: id, action: action) ?? false
            }
            ReminderService.shared.handleHabitAction = { [weak habits] id in
                await habits?.completeFromWidget(id: id) ?? false
            }
        } catch { fatalError("Unable to initialize Tenora's local store: \(error)") }
    }

    func publishWidget() {
        WidgetPublisher.publish(tasks: tasks.tasks, events: calendar.events,
            calendarKnown: calendar.availability != nil, focusedTaskID: tasks.focusedTaskID)
        WidgetPublisher.publishHabits(habits.widgetSnapshot)
    }
}
