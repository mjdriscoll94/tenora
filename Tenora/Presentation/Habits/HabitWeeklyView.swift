import SwiftUI

struct HabitWeeklyView: View {
    @EnvironmentObject private var store: HabitStore
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overview
                weekdayHeader
                ForEach(store.activeHabits) { habit in row(habit) }
                if store.activeHabits.isEmpty {
                    ContentUnavailableView("No habits yet", systemImage: "sparkles", description: Text("Create a habit to begin your weekly view."))
                }
            }.padding()
        }
        .background(TenoraScreenBackground()).navigationTitle("This Week")
    }

    private var dates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var summaries: [HabitDaySummary] { store.weeklySummary() }

    private var overview: some View {
        let scheduled = summaries.reduce(0) { $0 + $1.scheduled }
        let completed = summaries.reduce(0) { $0 + $1.completed }
        let xp = store.completions.filter { completion in dates.contains { calendar.isDate($0, inSameDayAs: completion.completionDate) } }.reduce(0) { $0 + $1.xpAwarded }
        return HStack {
            metric("Progress", scheduled == 0 ? "—" : (Double(completed) / Double(scheduled)).formatted(.percent.precision(.fractionLength(0))))
            metric("XP", "\(xp)")
            metric("Momentum", "\(store.progress.currentMomentum) days")
            metric("Perfect", "\(summaries.filter(\.isPerfect).count) days")
        }.padding(16).tenoraCard(cornerRadius: 18)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var weekdayHeader: some View {
        HStack {
            Text("QUEST").font(.caption2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(dates, id: \.self) { Text($0.formatted(.dateTime.weekday(.narrow))).font(.caption.weight(.bold)).frame(width: 25) }
        }.foregroundStyle(.secondary)
    }

    private func row(_ habit: Habit) -> some View {
        HStack {
            NavigationLink { HabitDetailView(habit: habit) } label: {
                HStack(spacing: 7) {
                    HabitArtworkView(iconName: habit.iconName, size: 28, tint: HabitTint.color(for: habit.colorIdentifier))
                    Text(habit.name).lineLimit(1)
                }
                .foregroundStyle(.primary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ForEach(dates, id: \.self) { date in
                let complete = store.isCompleted(habit, on: date)
                let scheduled = HabitGameEngine().scheduleCalculator.isScheduled(habit, on: date, completions: store.completions, calendar: calendar)
                Image(systemName: complete ? "checkmark.circle.fill" : scheduled ? "circle" : "minus")
                    .font(.caption).foregroundStyle(complete ? HabitTint.color(for: habit.colorIdentifier) : .secondary.opacity(scheduled ? 0.7 : 0.28)).frame(width: 25)
                    .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(complete ? "complete" : scheduled ? "open" : "not scheduled")")
            }
        }.padding(14).tenoraCard(cornerRadius: 15)
    }
}
