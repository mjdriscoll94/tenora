import SwiftUI

struct HabitWeeklyView: View {
    @EnvironmentObject private var store: HabitStore
    let anchorDate: Date
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(dateRange)
                    .font(.subheadline).foregroundStyle(.secondary)
                overview
                weekdayHeader
                ForEach(store.activeHabits) { habit in row(habit) }
                if store.activeHabits.isEmpty {
                    ContentUnavailableView("No habits yet", systemImage: "checklist", description: Text("Create a habit to begin tracking your week."))
                } else {
                    Text("Tap any past or current day to correct a check-in. Future days stay inactive until they arrive.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .background(TenoraScreenBackground()).navigationTitle(navigationTitle)
    }

    private var dates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var navigationTitle: String {
        calendar.isDate(anchorDate, equalTo: store.today, toGranularity: .weekOfYear)
            ? "This Week"
            : "Week of \(dates.first?.formatted(.dateTime.month(.abbreviated).day()) ?? "")"
    }

    private var dateRange: String {
        guard let first = dates.first, let last = dates.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var overview: some View {
        let summary = selectedWeekSummary
        return HStack(spacing: 0) {
            metric("Completed", "\(summary.completed) / \(summary.scheduled)")
            Divider().frame(height: 36)
            metric("Consistency", summary.scheduled == 0 ? "—" : summary.completionFraction.formatted(.percent.precision(.fractionLength(0))))
            Divider().frame(height: 36)
            metric("Active days", "\(summary.activeDays)")
        }
        .padding(16).tenoraCard(cornerRadius: 18)
    }

    private var selectedWeekSummary: HabitPeriodSummary {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate),
              let finalDay = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return .init() }
        return store.periodSummary(from: interval.start, through: min(calendar.startOfDay(for: store.today), finalDay))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayHeader: some View {
        HStack {
            Text("HABIT").font(.caption2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                    Text(date.formatted(.dateTime.day()))
                }
                .font(.caption2.weight(.bold)).frame(width: 30)
                .foregroundStyle(calendar.isDate(date, inSameDayAs: store.today) ? Color.tenoraCopper : .secondary)
            }
        }
    }

    private func row(_ habit: Habit) -> some View {
        let tint = HabitTint.color(for: habit.colorIdentifier)
        return HStack(spacing: 5) {
            NavigationLink { HabitDetailView(habit: habit) } label: {
                HStack(spacing: 8) {
                    HabitArtworkView(iconName: habit.iconName, size: 30, tint: tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name).lineLimit(1)
                        Text(habit.scheduleSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(dates, id: \.self) { date in
                let complete = store.isCompleted(habit, on: date)
                let scheduled = HabitTrackingEngine().scheduleCalculator.isScheduled(habit, on: date, completions: store.completions, calendar: calendar)
                let future = date > calendar.startOfDay(for: store.today)
                Button {
                    Task { await store.toggleCompletion(habit, on: date) }
                } label: {
                    ZStack {
                        Circle().fill(complete ? tint : scheduled ? Color.tenoraSage.opacity(0.16) : Color.clear)
                        Circle().stroke(scheduled ? tint.opacity(0.28) : Color.tenoraSage.opacity(0.16), lineWidth: 1)
                        Image(systemName: complete ? "checkmark" : scheduled ? "circle" : "minus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(complete ? .white : .secondary.opacity(0.65))
                    }
                    .frame(width: 28, height: 28).opacity(future ? 0.3 : 1)
                }
                .buttonStyle(.plain).disabled(future)
                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(complete ? "checked in" : scheduled ? "scheduled" : "not scheduled")")
            }
        }
        .padding(13).tenoraCard(cornerRadius: 15)
    }
}
