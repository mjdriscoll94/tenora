import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @EnvironmentObject private var transitionStore: TransitionStore
    @State private var reviewKind: ReviewKind?
    @State private var holdingTask: TenoraTask?
    @State private var showingLostTrackRecovery = false
    @State private var justStartTask: TenoraTask?
    @State private var stuckTask: TenoraTask?
    @AppStorage(AttentionPreferences.capacityModeKey) private var capacityModeRaw = TaskCapacityMode.balanced.rawValue
    @AppStorage(AttentionPreferences.capacitySelectedAtKey) private var capacitySelectedAt = 0.0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(calendarStore.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                lostTrackCard
                if let task = taskStore.activeJustStartTask {
                    Button {
                        justStartTask = task
                    } label: {
                        Label("Continue short start: \(task.nextStep ?? task.title)", systemImage: "timer")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(TenoraPrimaryButtonStyle())
                }
                capacityPicker
                nowSection

                if !remainingKeptInFrontTasks.isEmpty {
                    keptInFrontSection
                }

                if !horizonItems.isEmpty { horizonSection }

                if !remainingResurfacedTasks.isEmpty {
                    resurfacedSection
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("A MOMENT TO REORIENT")
                    HStack(spacing: 12) {
                        Button("Morning review") { reviewKind = .morning }.buttonStyle(TenoraSecondaryButtonStyle())
                        Button("Evening reset") { reviewKind = .evening }.buttonStyle(TenoraSecondaryButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(TenoraScreenBackground())
        .navigationTitle("Today")
        .sheet(item: $reviewKind) { ReviewView(kind: $0) }
        .sheet(item: $holdingTask) { HoldPlaceView(task: $0) }
        .sheet(isPresented: $showingLostTrackRecovery) {
            LostTrackRecoveryView(
                availableMinutes: calendarStore.availability?.availableMinutes,
                capacityMode: capacityMode
            )
        }
        .sheet(item: $justStartTask) { JustStartView(task: $0) }
        .sheet(item: $stuckTask) { StuckAssistanceView(task: $0) }
        .overlay(alignment: .bottom) {
            if let errorMessage = taskStore.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private var lostTrackCard: some View {
        Button { showingLostTrackRecovery = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.tenoraCopper)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOST THE THREAD?")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.tenoraCopper)
                    Text("What was I doing?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let task = taskStore.recoveryTask {
                        Text(task.nextStep.flatMap { $0.isEmpty ? nil : "Next: \($0)" } ?? task.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("Tenora will help you find one clear place to begin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tenoraCard(cornerRadius: 16)
        .accessibilityLabel("What was I doing?")
    }

    @ViewBuilder
    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOW")

            if let task = recommendation {
                VStack(alignment: .leading, spacing: 16) {
                    Text("WHAT MATTERS NOW")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.tenoraSage)

                    Text(task.title)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    if let step = task.nextStep, !step.isEmpty {
                        Text("Next: \(step)").foregroundStyle(.white.opacity(0.9))
                    }

                    NavigationLink("Edit or schedule") { TaskDetailView(task: task) }
                        .font(.subheadline).foregroundStyle(.white)

                    if let duration = task.estimatedDurationMinutes {
                        Label("About \(duration) minutes", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    availabilityContext
                    Text(taskStore.reason(for: task, availableMinutes: calendarStore.availability?.availableMinutes, capacityMode: capacityMode))
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    if taskStore.focusedTaskID != task.id {
                        Button("Start") { Task { await taskStore.start(task) } }
                            .buttonStyle(TenoraPrimaryButtonStyle())
                    }
                    Button(task.justStartEndsAt == nil ? "Just Start" : "Continue short start") { justStartTask = task }
                        .buttonStyle(.bordered).tint(.white)
                    Button("I'm stuck") { stuckTask = task }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Hold my place") { holdingTask = task }.tint(.white)
                    Button {
                        Task { await taskStore.setKeepInFrontToday(!task.isKeptInFront(at: calendarStore.currentDate), for: task.id) }
                    } label: {
                        Label(
                            task.isKeptInFront(at: calendarStore.currentDate) ? "Kept in front today" : "Keep in front today",
                            systemImage: task.isKeptInFront(at: calendarStore.currentDate) ? "pin.fill" : "pin"
                        )
                    }
                    .tint(.white)

                    HStack {
                        Button("Complete") {
                            Task { await taskStore.complete(task) }
                        }
                        .buttonStyle(TenoraPrimaryButtonStyle())

                        Button("Later") {
                            Task { await taskStore.postpone(task) }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(TenoraNowCardBackground())
                .shadow(color: Color.tenoraInk.opacity(0.18), radius: 18, y: 10)
                .accessibilityElement(children: .contain)
            } else {
                ContentUnavailableView(
                    calendarStore.availability?.currentEvent != nil ? "Your calendar has this time" : "Nothing needs you right now",
                    systemImage: "checkmark.circle",
                    description: Text("Tenora holds your tasks for an available moment in your working hours. You can always find them in Inbox.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder
    private var availabilityContext: some View {
        if let snapshot = calendarStore.availability,
           let nextEvent = snapshot.nextEvent,
           let minutes = snapshot.availableMinutes,
           minutes == snapshot.minutesUntilNextEvent,
           minutes > 0 {
            Text("You have \(minutes) minutes before \(nextEvent.title).")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        } else if let minutes = calendarStore.availability?.availableMinutes, minutes > 0 {
            Text("You have about \(minutes) minutes available.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var horizonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([DayHorizonPhase.soon, .later], id: \.rawValue) { phase in
                let phaseItems = horizonItems.filter { $0.phase == phase }
                if !phaseItems.isEmpty {
                sectionLabel(phase.rawValue.uppercased())
                VStack(spacing: 0) {
                    ForEach(Array(phaseItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                        horizonRow(item)
                        if index < min(phaseItems.count, 5) - 1 { Divider() }
                    }
                }
                .padding(.horizontal)
                .tenoraCard()
                }
            }
        }
    }

    private var capacityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WHAT CAN YOU HANDLE RIGHT NOW?")
            Menu {
                ForEach(TaskCapacityMode.allCases) { mode in
                    Button {
                        selectCapacity(mode)
                    } label: {
                        Label(mode.title, systemImage: mode == capacityMode ? "checkmark" : mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: capacityMode.icon)
                        .font(.title3)
                        .foregroundStyle(Color.tenoraCopper)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capacityMode.shortTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(capacityMode == .balanced ? "Tenora will balance urgency, timing, and fit." : "Recommendations will favor this kind of task for today.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tenoraCard(cornerRadius: 16)
            .accessibilityIdentifier("capacity-picker")
        }
    }

    private var keptInFrontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("IN FRONT TODAY")
            VStack(spacing: 0) {
                ForEach(Array(remainingKeptInFrontTasks.enumerated()), id: \.element.id) { index, task in
                    HStack(spacing: 12) {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(Color.tenoraCopper)
                            .accessibilityHidden(true)
                        NavigationLink { TaskDetailView(task: task) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.body.weight(.medium))
                                if let step = task.nextStep, !step.isEmpty {
                                    Text("Next: \(step)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button {
                            Task { await taskStore.setKeepInFrontToday(false, for: task.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop keeping \(task.title) in front today")
                    }
                    .padding(.vertical, 12)
                    if index < remainingKeptInFrontTasks.count - 1 { Divider() }
                }
            }
            .padding(.horizontal)
            .tenoraCard()
        }
    }

    @ViewBuilder
    private func horizonRow(_ item: DayHorizonItem) -> some View {
        if case .task(let id) = item.kind, let task = taskStore.tasks.first(where: { $0.id == id }) {
            NavigationLink { TaskDetailView(task: task) } label: { horizonRowContent(item) }
        } else {
            horizonRowContent(item)
        }
    }

    private func horizonRowContent(_ item: DayHorizonItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(item.date.formatted(date: Calendar.current.isDate(item.date, inSameDayAs: calendarStore.currentDate) ? .omitted : .abbreviated, time: .shortened))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tenoraCopper)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium))
                if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private var horizonItems: [DayHorizonItem] {
        DayHorizonEngine().items(tasks: taskStore.tasks, events: calendarStore.upcomingEvents,
                                 transitions: transitionStore.plans, now: calendarStore.currentDate)
    }

    private var resurfacedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RESURFACED")
            ForEach(remainingResurfacedTasks) { task in
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is ready for another look:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(task.title)
                        .font(.headline)
                    NavigationLink(task.snoozeCount >= 3 ? "Still important? Schedule or let go" : "Edit or schedule") { TaskDetailView(task: task) }
                    HStack {
                        Button("Done") {
                            Task { await taskStore.complete(task) }
                        }
                        Button("Later") {
                            Task { await taskStore.postpone(task) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .tenoraCard(cornerRadius: 16)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.tenoraCopper)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var remainingResurfacedTasks: [TenoraTask] {
        let context = TaskPriorityEngine.Context(now: calendarStore.currentDate, availableMinutes: calendarStore.availability?.availableMinutes, schedule: AttentionPreferences.schedule)
        return Array(taskStore.resurfacedTasks.filter {
            $0.id != recommendation?.id
                && !$0.isKeptInFront(at: calendarStore.currentDate)
                && TaskPriorityEngine().isEligible($0, context: context)
        }.prefix(2))
    }

    private var remainingKeptInFrontTasks: [TenoraTask] {
        taskStore.keptInFrontTasks.filter { $0.id != recommendation?.id }
    }

    private var recommendation: TenoraTask? {
        taskStore.recommendation(availableMinutes: calendarStore.availability?.availableMinutes, capacityMode: capacityMode)
    }

    private var capacityMode: TaskCapacityMode {
        AttentionPreferences.capacityMode(
            rawValue: capacityModeRaw,
            selectedAt: capacitySelectedAt,
            now: calendarStore.currentDate
        )
    }

    private func selectCapacity(_ mode: TaskCapacityMode) {
        capacityModeRaw = mode.rawValue
        capacitySelectedAt = mode == .balanced ? 0 : calendarStore.currentDate.timeIntervalSince1970
        WidgetPublisher.publish(
            tasks: taskStore.tasks,
            events: calendarStore.events,
            calendarKnown: calendarStore.availability != nil,
            focusedTaskID: taskStore.focusedTaskID
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.tenoraCopper)
            .tracking(1.2)
    }
}
