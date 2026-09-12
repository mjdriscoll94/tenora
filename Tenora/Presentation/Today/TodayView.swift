import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var reviewKind: ReviewKind?
    @State private var holdingTask: TenoraTask?
    @State private var showingResume = false
    @State private var justStartTask: TenoraTask?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(calendarStore.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let task = taskStore.resumeTask {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("YOUR PLACE IS HELD")
                        Text(task.title).font(.headline)
                        if let step = task.nextStep, !step.isEmpty { Text("Next: \(step)").foregroundStyle(.secondary) }
                        Button("What was I doing?") { showingResume = true }.buttonStyle(.bordered)
                    }
                }
                if let task = taskStore.activeJustStartTask {
                    Button {
                        justStartTask = task
                    } label: {
                        Label("Continue short start: \(task.nextStep ?? task.title)", systemImage: "timer")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderedProminent)
                }
                nowSection

                if !calendarStore.upcomingEvents.isEmpty {
                    comingUpSection
                }

                if !remainingResurfacedTasks.isEmpty {
                    resurfacedSection
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("A MOMENT TO REORIENT")
                    Button("Morning review") { reviewKind = .morning }.buttonStyle(.bordered)
                    Button("Evening reset") { reviewKind = .evening }.buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.tenoraSurface.ignoresSafeArea())
        .navigationTitle("Today")
        .sheet(item: $reviewKind) { ReviewView(kind: $0) }
        .sheet(item: $holdingTask) { HoldPlaceView(task: $0) }
        .sheet(isPresented: $showingResume) { ResumeView() }
        .sheet(item: $justStartTask) { JustStartView(task: $0) }
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

    @ViewBuilder
    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOW")

            if let task = recommendation {
                VStack(alignment: .leading, spacing: 16) {
                    Text("WHAT MATTERS NOW")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.tenoraLavender)

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
                    Text(taskStore.reason(for: task, availableMinutes: calendarStore.availability?.availableMinutes))
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    if taskStore.focusedTaskID != task.id {
                        Button("Start") { Task { await taskStore.start(task) } }
                            .buttonStyle(TenoraPrimaryButtonStyle())
                    }
                    Button(task.justStartEndsAt == nil ? "Just Start" : "Continue short start") { justStartTask = task }
                        .buttonStyle(.bordered).tint(.white)
                    Button("Hold my place") { holdingTask = task }.tint(.white)

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
                .shadow(color: Color.tenoraNavy.opacity(0.18), radius: 18, y: 10)
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

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("COMING UP")
            VStack(spacing: 0) {
                ForEach(Array(calendarStore.upcomingEvents.prefix(3).enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(event.isAllDay ? "All day" : event.startDate.formatted(date: Calendar.current.isDate(event.startDate, inSameDayAs: calendarStore.currentDate) ? .omitted : .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.tenoraBlue)
                            .frame(width: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.body.weight(.medium))
                            if !event.calendarName.isEmpty {
                                Text(event.calendarName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)

                    if index < min(calendarStore.upcomingEvents.count, 3) - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
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
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(TenoraTheme.accentGradient)
                        .frame(width: 4)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var remainingResurfacedTasks: [TenoraTask] {
        let context = TaskPriorityEngine.Context(now: calendarStore.currentDate, availableMinutes: calendarStore.availability?.availableMinutes, schedule: AttentionPreferences.schedule)
        return Array(taskStore.resurfacedTasks.filter { $0.id != recommendation?.id && TaskPriorityEngine().isEligible($0, context: context) }.prefix(2))
    }

    private var recommendation: TenoraTask? {
        taskStore.recommendation(availableMinutes: calendarStore.availability?.availableMinutes)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.tenoraBlue)
            .tracking(1.2)
    }
}
