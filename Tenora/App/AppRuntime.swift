import Foundation
import SwiftData

/// One container and repository shared by the application and its foreground intents.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let container: ModelContainer
    let persistenceIssue: PersistenceIssue?
    let tasks: TaskStore
    let calendar: CalendarStore
    let transitions: TransitionStore
    let habits: HabitStore
    let appSettings: AppSettingsStore
    let profileID: LocalProfileID
    let settings: SettingsRepository
    let outbox: MutationOutbox?
    let personalSyncInventoryReport: PersonalSyncInventoryReport?

    private init() {
        let uiTesting: Bool
        #if DEBUG
        uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        uiTesting = false
        #endif

        let profileRepository = UserDefaultsProfileRepository()
        profileID = profileRepository.activeProfileID
        settings = UserDefaultsSettingsRepository(profileID: profileID)
        appSettings = AppSettingsStore(repository: settings)
        ReminderService.shared.configure(settings: settings)

        let resolvedContainer: ModelContainer
        let resolvedIssue: PersistenceIssue?
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-reset-working-schedule") {
                UserDefaults.standard.removeObject(forKey: AttentionPreferences.scheduleKey)
            }
            if uiTesting {
                resolvedContainer = try TenoraModelContainerFactory.makeInMemory()
            } else {
                resolvedContainer = try TenoraModelContainerFactory.makePersistent(profileID: profileID)
            }
            #else
            resolvedContainer = try TenoraModelContainerFactory.makePersistent(profileID: profileID)
            #endif
            resolvedIssue = nil
        } catch {
            resolvedIssue = PersistenceIssue(
                title: "Tenora couldn't open your saved data",
                message: "Nothing was deleted. Tenora opened a temporary recovery store so the original data remains untouched.",
                technicalDetails: String(describing: error)
            )
            do {
                resolvedContainer = try TenoraModelContainerFactory.makeInMemory()
            } catch {
                fatalError("Unable to initialize Tenora's recovery store: \(error)")
            }
        }

        container = resolvedContainer
        persistenceIssue = resolvedIssue
        let transactionalOutbox = SwiftDataMutationOutbox(modelContext: container.mainContext)
        if let legacyOutbox = try? FileMutationOutbox() {
            _ = try? legacyOutbox.migratePending(profileID: profileID, to: transactionalOutbox)
        }
        outbox = transactionalOutbox
        personalSyncInventoryReport = try? PersonalSyncMetadataStore(modelContext: container.mainContext)
            .backfill(profileID: profileID)
        tasks = TaskStore(
            repository: SwiftDataTaskRepository(
                modelContext: container.mainContext,
                profileID: profileID,
                outbox: outbox
            ),
            settings: settings
        )
        let habitRepository = SwiftDataHabitRepository(
            modelContext: container.mainContext,
            profileID: profileID,
            outbox: outbox
        )
        habits = HabitStore(
            habitRepository: habitRepository,
            completionRepository: habitRepository,
            progressRepository: habitRepository,
            retainedRepository: habitRepository
        )
        let calendarRepository = EventKitCalendarRepository()
        calendar = CalendarStore(repository: calendarRepository, settings: settings)
        transitions = TransitionStore(repository: UserDefaultsTransitionRepository(settings: settings, outbox: outbox))

        do {
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
        } catch {
            assertionFailure("Unable to prepare Tenora's UI-test fixture: \(error)")
        }
    }

    func publishWidget() {
        WidgetPublisher.publish(tasks: tasks.tasks, events: calendar.events,
            calendarKnown: calendar.availability != nil, focusedTaskID: tasks.focusedTaskID,
            profileID: profileID, settings: settings)
        WidgetPublisher.publishHabits(habits.widgetSnapshot, profileID: profileID)
    }
}

struct PersistenceIssue: Equatable, Sendable {
    let title: String
    let message: String
    let technicalDetails: String
}
