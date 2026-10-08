import SwiftUI
import UIKit

struct HabitDashboardView: View {
    private enum Scope: CaseIterable, Identifiable {
        case scheduled
        case all
        var id: Self { self }
    }

    @EnvironmentObject private var store: HabitStore
    @AppStorage("habits.intro.seen") private var hasSeenIntro = false
    @State private var showingEditor = false
    @State private var showingIntro = false
    @State private var scope: Scope = .scheduled
    @State private var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                dateNavigator

                if store.activeHabits.isEmpty {
                    emptyState
                } else {
                    dayOverview
                    weekCard
                    habitList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .background(TenoraScreenBackground())
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: { Label("Create habit", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) { HabitEditorView() }
        .sheet(isPresented: $showingIntro, onDismiss: { hasSeenIntro = true }) {
            HabitIntroView { hasSeenIntro = true; showingIntro = false; showingEditor = true }
        }
        .task {
            await store.load()
            if !hasSeenIntro && store.activeHabits.isEmpty && !ProcessInfo.processInfo.arguments.contains("-habit-tracker-test") { showingIntro = true }
        }
        .overlay(alignment: .bottom) {
            if let error = store.errorMessage {
                Text(error).font(.footnote).padding(10).background(.regularMaterial, in: Capsule()).padding()
            }
        }
    }

    private var dateNavigator: some View {
        HStack(spacing: 12) {
            dateButton(symbol: "chevron.left", label: "Previous day", identifier: "habit-previous-day") {
                moveSelectedDate(by: -1)
            }

            VStack(spacing: 2) {
                Text(relativeDayTitle)
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Color.tenoraCopper)
                    .accessibilityIdentifier("habit-selected-day-label")
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)

            if isSelectedToday {
                dateButton(symbol: "chevron.right", label: "Next day", identifier: "habit-next-day", disabled: true) {}
            } else {
                Button("Today") { selectDate(store.today) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tenoraForest)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("habit-return-today")

                dateButton(symbol: "chevron.right", label: "Next day", identifier: "habit-next-day") {
                    moveSelectedDate(by: 1)
                }
            }
        }
        .padding(12)
        .tenoraCard(cornerRadius: 18)
    }

    private func dateButton(
        symbol: String,
        label: String,
        identifier: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 42, height: 42)
                .background(Color.tenoraSage.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.tenoraForest)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var dayOverview: some View {
        let summary = store.daySummary(on: selectedDate)
        let remaining = max(0, summary.scheduled - summary.completed)
        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(relativeDayTitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.tenoraSage)
                Text(dayHeadline(summary: summary))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(dayDetail(summary: summary, remaining: remaining))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            HabitProgressRing(completed: summary.completed, total: summary.scheduled)
        }
        .padding(20)
        .background(TenoraNowCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("habit-today-summary")
    }

    private func dayHeadline(summary: HabitDaySummary) -> String {
        guard summary.scheduled > 0 else { return "Nothing scheduled" }
        if summary.completed == summary.scheduled { return "All checked in" }
        return "\(summary.completed) of \(summary.scheduled) complete"
    }

    private func dayDetail(summary: HabitDaySummary, remaining: Int) -> String {
        guard summary.scheduled > 0 else { return "Your habits are still here when their next scheduled day arrives." }
        if remaining == 0 { return isSelectedToday ? "You’re done for today. The rest can wait." : "Everything scheduled for this day was checked in." }
        if summary.completed == 0 { return isSelectedToday ? "Start with whichever one feels easiest to reach." : "You can still add any check-ins you remember." }
        if isSelectedToday { return remaining == 1 ? "One habit remains today." : "\(remaining) habits remain today." }
        return remaining == 1 ? "One check-in is still open for this day." : "\(remaining) check-ins are still open for this day."
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                NavigationLink { HabitWeeklyView(anchorDate: selectedDate) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weekTitle)
                            .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
                        let summary = selectedWeekSummary
                        Text(summary.scheduled == 0 ? "No check-ins due yet" : "\(summary.completed) of \(summary.scheduled) completed so far")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                ForEach(weekDates, id: \.self) { date in
                    let isFuture = date > calendar.startOfDay(for: store.today)
                    Button { selectDate(date) } label: {
                        WeekDayProgressCell(
                            date: date,
                            summary: store.daySummary(on: date),
                            isToday: calendar.isDate(date, inSameDayAs: store.today),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isFuture: isFuture
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                    .accessibilityIdentifier("habit-week-day-\(calendar.component(.weekday, from: date))")
                }
            }
        }
        .padding(16)
        .tenoraCard(cornerRadius: 20)
        .accessibilityIdentifier("habit-week-summary")
    }

    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedWeekSummary: HabitPeriodSummary {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate),
              let finalDay = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return .init() }
        return store.periodSummary(from: interval.start, through: min(calendar.startOfDay(for: store.today), finalDay))
    }

    private var weekTitle: String {
        if calendar.isDate(selectedDate, equalTo: store.today, toGranularity: .weekOfYear) { return "THIS WEEK" }
        guard let start = weekDates.first else { return "SELECTED WEEK" }
        return "WEEK OF \(start.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Habit view", selection: $scope) {
                Text(isSelectedToday ? "Today" : "Selected day").tag(Scope.scheduled)
                Text("All habits").tag(Scope.all)
            }
            .pickerStyle(.segmented)

            let scheduledHabits = store.scheduledHabits(on: selectedDate)
            let habits = scope == .scheduled ? scheduledHabits : store.activeHabits
            if habits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: scope == .scheduled ? "calendar.badge.checkmark" : "checklist")
                        .font(.title2).foregroundStyle(Color.tenoraCopper)
                    Text(scope == .scheduled ? (isSelectedToday ? "No habits are scheduled today" : "No habits were scheduled for this day") : "No active habits")
                        .font(.headline)
                    Text(scope == .scheduled ? "Switch to All habits to review or edit your routines." : "Create a habit when you’re ready.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(24).tenoraCard(cornerRadius: 18)
            } else {
                ForEach(habits) { habit in
                    HabitTrackingRow(
                        habit: habit,
                        date: selectedDate,
                        scheduledOnDate: scheduledHabits.contains(where: { $0.id == habit.id })
                    )
                }
            }
        }
    }

    private var isSelectedToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: store.today)
    }

    private var relativeDayTitle: String {
        if isSelectedToday { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private func moveSelectedDate(by days: Int) {
        guard let candidate = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectDate(candidate)
    }

    private func selectDate(_ date: Date) {
        let today = calendar.startOfDay(for: store.today)
        let candidate = calendar.startOfDay(for: date)
        guard candidate <= today else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedDate = candidate }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(TenoraTheme.calmGradient).frame(width: 84, height: 84)
                Image(systemName: "checklist.checked")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.tenoraForest)
            }
            Text("A clearer way to keep track").font(.title2.bold())
            Text("Choose a habit, set a realistic rhythm, and check it off once a day. Tenora keeps the history easy to correct and understand.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showingEditor = true } label: { Text("Create a Habit").frame(maxWidth: .infinity) }
                .buttonStyle(TenoraPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(26).tenoraCard(cornerRadius: 22)
    }
}

private struct HabitProgressRing: View {
    let completed: Int
    let total: Int

    private var fraction: Double { total == 0 ? 0 : min(1, Double(completed) / Double(total)) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(TenoraTheme.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(completed)").font(.title2.bold())
                Text("of \(total)").font(.caption2).foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 82, height: 82)
    }
}

private struct WeekDayProgressCell: View {
    let date: Date
    let summary: HabitDaySummary
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool

    private var complete: Bool { summary.scheduled > 0 && summary.completed == summary.scheduled }

    var body: some View {
        VStack(spacing: 7) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .fill(complete ? Color.tenoraForest : Color.tenoraSage.opacity(isFuture ? 0.08 : 0.16))
                if complete {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else if summary.scheduled > 0 && !isFuture {
                    Text("\(summary.completed)/\(summary.scheduled)").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.tenoraForest)
                } else {
                    Image(systemName: summary.scheduled > 0 ? "circle.dotted" : "minus")
                        .font(.caption2).foregroundStyle(.secondary.opacity(0.55))
                }
            }
            .frame(width: 34, height: 34)
            .overlay { Circle().stroke(isSelected ? Color.tenoraCopper : Color.clear, lineWidth: 2.5) }
            .overlay(alignment: .bottom) {
                if isToday && !isSelected { Circle().fill(Color.tenoraCopper).frame(width: 5, height: 5).offset(y: 5) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(summary.completed) of \(summary.scheduled) complete")
    }
}

private struct HabitTrackingRow: View {
    @EnvironmentObject private var store: HabitStore
    let habit: Habit
    let date: Date
    let scheduledOnDate: Bool

    private var completed: Bool { store.isCompleted(habit, on: date) }
    private var tint: Color { HabitTint.color(for: habit.colorIdentifier) }
    private var isToday: Bool { Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: store.today) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.13))
                HabitArtworkView(iconName: habit.iconName, size: 46, tint: tint, completed: completed)
            }
            .frame(width: 52, height: 52)

            NavigationLink { HabitDetailView(habit: habit) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .font(.headline).foregroundStyle(.primary)
                        .strikethrough(completed, color: .secondary)
                    Text(rowDetail)
                        .font(.caption).foregroundStyle(.secondary)
                    if !scheduledOnDate {
                        Text(habit.scheduleSummary).font(.caption2.weight(.medium)).foregroundStyle(tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if scheduledOnDate || completed {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await store.toggleCompletion(habit, on: date) }
                } label: {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30, weight: .regular)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completed ? "Undo completion for \(habit.name) on \(formattedDate)" : "Complete \(habit.name) on \(formattedDate)")
                .accessibilityIdentifier("habit-toggle-\(habit.name)")
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .padding(15)
        .tenoraCard(cornerRadius: 18)
        .accessibilityAction(named: completed ? "Undo" : "Complete") {
            guard scheduledOnDate || completed else { return }
            Task { await store.toggleCompletion(habit, on: date) }
        }
    }

    private var rowDetail: String {
        if completed { return isToday ? "Checked in today" : "Checked in \(formattedDate)" }
        if scheduledOnDate { return isToday ? store.recentConsistencyText(for: habit) : "Scheduled for \(formattedDate)" }
        return "Not scheduled for \(formattedDate)"
    }

    private var formattedDate: String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct HabitIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    let onCreate: () -> Void

    private let pages = [
        ("checkmark.circle", "Keep today simple", "See only the habits that are due and check each one off with a single tap."),
        ("calendar", "Use a rhythm that fits", "Choose every day, specific weekdays, a weekly target, or a custom interval."),
        ("chart.bar", "Notice patterns, not perfection", "Review your week and correct past check-ins without losing the bigger picture.")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: 20) {
                            Image(systemName: pages[index].0).font(.system(size: 54)).foregroundStyle(TenoraTheme.accentGradient)
                            Text(pages[index].1).font(.title.bold()).multilineTextAlignment(.center)
                            Text(pages[index].2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(30).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(page == pages.count - 1 ? "Create Your First Habit" : "Continue") {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { onCreate() }
                }
                .buttonStyle(TenoraPrimaryButtonStyle())
                Button("Not now") { dismiss() }.foregroundStyle(.secondary)
            }
            .padding().background(TenoraScreenBackground())
            .navigationTitle("How Habits Work").navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
#Preview("Empty") { NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.empty)) }
#Preview("In progress") { NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.partial)) }
#Preview("Complete") { NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.perfect)) }
#Preview("Dark mode") { NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.partial)).preferredColorScheme(.dark) }
#endif
