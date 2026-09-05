import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var calendarStore: CalendarStore
    @State private var reviewKind: ReviewKind?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(calendarStore.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

                    NavigationLink("Edit or schedule") { TaskDetailView(task: task) }
                        .font(.subheadline).foregroundStyle(.white)

                    if let duration = task.estimatedDurationMinutes {
                        Label("About \(duration) minutes", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    availabilityContext

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
                    "Nothing needs you right now",
                    systemImage: "checkmark.circle",
                    description: Text("Capture something and Tenora will hold your place.")
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
                        Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
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
        taskStore.resurfacedTasks.filter { $0.id != recommendation?.id }
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
