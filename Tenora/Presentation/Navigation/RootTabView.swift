import SwiftUI

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @EnvironmentObject private var transitionStore: TransitionStore
    @EnvironmentObject private var habitStore: HabitStore
    @State private var isAddingTask = false
    @ObservedObject private var reminders = ReminderService.shared
    @State private var openedTask: TenoraTask?
    @State private var openedHabit: Habit?
    @State private var captureTitle = ""
    @State private var selectedTab = 0
    @State private var missingTask = false
    @State private var showingResume = false
    @State private var returnSince: Date?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                InboxView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .tag(1)

            NavigationStack {
                CalendarView()
                    .toolbar { addButton }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(2)

            NavigationStack {
                HabitDashboardView()
                    .toolbar { settingsButton }
            }
            .tabItem { Label("Habits", systemImage: "checkmark.circle") }
            .tag(3)
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskView(initialTitle: captureTitle, onResume: { selectedTab = 0 })
        }
        .tint(.tenoraForest)
        .toolbarBackground(Color.tenoraCard, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showingResume) {
            LostTrackRecoveryView(
                since: returnSince,
                availableMinutes: calendarStore.availability?.availableMinutes,
                capacityMode: currentCapacityMode,
                onRecover: { selectedTab = 0 }
            )
        }
        .onOpenURL { url in
            guard let route = TenoraRoute(url: url) else { return }
            showingResume = false
            Task {
                await taskStore.load()
                switch route {
                case .capture(let title):
                    openedTask = nil
                    captureTitle = title
                    isAddingTask = true
                case .task(let id):
                    isAddingTask = false
                    openedTask = taskStore.tasks.first { $0.id == id }
                    missingTask = openedTask == nil
                case .today: selectedTab = 0
                case .habits: selectedTab = 3
                case .habit(let id):
                    await habitStore.load()
                    selectedTab = 3
                    openedHabit = habitStore.habits.first { $0.id == id }
                }
            }
        }
        .alert("This task is no longer available", isPresented: $missingTask) { Button("OK", role: .cancel) {} }
        .sheet(item: $openedTask) { task in NavigationStack { TaskDetailView(task: task) } }
        .sheet(item: $openedHabit) { habit in NavigationStack { HabitDetailView(habit: habit) } }
        .onChange(of: reminders.openedTaskID) { _, id in
            guard let id else { return }
            showingResume = false
            Task {
                await taskStore.load()
                openedTask = taskStore.tasks.first { $0.id == id }
                reminders.openedTaskID = nil
            }
        }
        .onChange(of: reminders.openedHabitID) { _, id in
            guard let id else { return }
            Task {
                await habitStore.load()
                selectedTab = 3
                openedHabit = habitStore.habits.first { $0.id == id }
                reminders.openedHabitID = nil
            }
        }
        .onChange(of: settings.legacyWorkStart) { _, _ in Task { await calendarStore.refresh() } }
        .onChange(of: settings.legacyWorkEnd) { _, _ in Task { await calendarStore.refresh() } }
        .onChange(of: settings.workingScheduleJSON) { _, _ in Task { await calendarStore.refresh(); await taskStore.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { settings.lastLeft = Date().timeIntervalSince1970 }
        }
        .task(id: scenePhase) {
            await handleScenePhase()
        }
    }

    private var currentCapacityMode: TaskCapacityMode {
        settings.capacityMode(at: Date())
    }

    private func handleScenePhase() async {
        guard scenePhase == .active else { return }
        if TenoraFeatures.agentBridgeEnabled { await AgentBridgeSyncService.shared.warmUp() }
        await taskStore.load()
        await habitStore.load()
        await habitStore.drainWidgetActions()
        if shouldOfferRecovery {
            returnSince = Date(timeIntervalSince1970: settings.lastLeft)
            showingResume = true
        }
        settings.lastLeft = 0
        repeat {
            await taskStore.load()
            await habitStore.load()
            await habitStore.drainWidgetActions()
            await calendarStore.refresh()
            await taskStore.resolveReturnTriggers(events: calendarStore.events, availability: calendarStore.availability)
            await transitionStore.synchronize(events: calendarStore.events)
            await reminders.drainActions()
            if let id = reminders.openedTaskID {
                openedTask = taskStore.tasks.first { $0.id == id }
                reminders.openedTaskID = nil
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        } while !Task.isCancelled
    }

    private var shouldOfferRecovery: Bool {
        settings.shouldOfferRecovery(now: Date())
            && taskStore.resumeTask != nil
            && !isAddingTask
            && openedTask == nil
            && reminders.openedTaskID == nil
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                captureTitle = ""
                isAddingTask = true
            } label: {
                Label("Add task", systemImage: "plus")
            }
        }
    }

    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
        }
    }
}
