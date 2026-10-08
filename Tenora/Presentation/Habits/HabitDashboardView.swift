import SwiftUI
import UIKit

struct HabitDashboardView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case today = "Today"
        case all = "All habits"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: HabitStore
    @AppStorage("habits.intro.seen") private var hasSeenIntro = false
    @State private var showingEditor = false
    @State private var showingIntro = false
    @State private var scope: Scope = .today

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                Text(store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if store.activeHabits.isEmpty {
                    emptyState
                } else {
                    todayOverview
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

    private var todayOverview: some View {
        let summary = store.todaySummary
        let remaining = max(0, summary.scheduled - summary.completed)
        return HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.tenoraSage)
                Text(todayHeadline(summary: summary))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(todayDetail(summary: summary, remaining: remaining))
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

    private func todayHeadline(summary: HabitDaySummary) -> String {
        guard summary.scheduled > 0 else { return "Nothing due today" }
        if summary.completed == summary.scheduled { return "All checked in" }
        return "\(summary.completed) of \(summary.scheduled) complete"
    }

    private func todayDetail(summary: HabitDaySummary, remaining: Int) -> String {
        guard summary.scheduled > 0 else { return "Your habits are still here when their next scheduled day arrives." }
        if remaining == 0 { return "You’re done for today. The rest can wait." }
        if summary.completed == 0 { return "Start with whichever one feels easiest to reach." }
        return remaining == 1 ? "One habit remains today." : "\(remaining) habits remain today."
    }

    private var weekCard: some View {
        NavigationLink { HabitWeeklyView() } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("THIS WEEK")
                            .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
                        let summary = store.thisWeekSummary()
                        Text(summary.scheduled == 0 ? "No check-ins due yet" : "\(summary.completed) of \(summary.scheduled) completed so far")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    ForEach(weekDates, id: \.self) { date in
                        WeekDayProgressCell(
                            date: date,
                            summary: store.daySummary(on: date),
                            isToday: calendar.isDate(date, inSameDayAs: store.today),
                            isFuture: date > calendar.startOfDay(for: store.today)
                        )
                    }
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tenoraCard(cornerRadius: 20)
        .accessibilityIdentifier("habit-week-summary")
    }

    private var weekDates: [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: store.today)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Habit view", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let habits = scope == .today ? store.todayHabits : store.activeHabits
            if habits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: scope == .today ? "calendar.badge.checkmark" : "checklist")
                        .font(.title2).foregroundStyle(Color.tenoraCopper)
                    Text(scope == .today ? "No habits are scheduled today" : "No active habits")
                        .font(.headline)
                    Text(scope == .today ? "Switch to All habits to review or edit your routines." : "Create a habit when you’re ready.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(24).tenoraCard(cornerRadius: 18)
            } else {
                ForEach(habits) { habit in
                    HabitTrackingRow(habit: habit, scheduledToday: store.todayHabits.contains(where: { $0.id == habit.id }))
                }
            }
        }
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
            .overlay { Circle().stroke(isToday ? Color.tenoraCopper : Color.clear, lineWidth: 2) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)): \(summary.completed) of \(summary.scheduled) complete")
    }
}

private struct HabitTrackingRow: View {
    @EnvironmentObject private var store: HabitStore
    let habit: Habit
    let scheduledToday: Bool

    private var completed: Bool { store.isCompleted(habit) }
    private var tint: Color { HabitTint.color(for: habit.colorIdentifier) }

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
                    Text(store.recentConsistencyText(for: habit))
                        .font(.caption).foregroundStyle(.secondary)
                    if !scheduledToday {
                        Text(habit.scheduleSummary).font(.caption2.weight(.medium)).foregroundStyle(tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if scheduledToday {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await store.toggleCompletion(habit) }
                } label: {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30, weight: .regular)).foregroundStyle(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(completed ? "Undo completion for \(habit.name)" : "Complete \(habit.name)")
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .padding(15)
        .tenoraCard(cornerRadius: 18)
        .accessibilityAction(named: completed ? "Undo" : "Complete") {
            guard scheduledToday else { return }
            Task { await store.toggleCompletion(habit) }
        }
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
