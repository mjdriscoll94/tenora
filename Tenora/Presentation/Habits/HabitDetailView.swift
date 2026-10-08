import SwiftUI

struct HabitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HabitStore
    let habit: Habit
    @State private var showingEditor = false
    @State private var showingDelete = false

    private let calendar = Calendar.autoupdatingCurrent
    private var current: Habit { store.habits.first(where: { $0.id == habit.id }) ?? habit }
    private var recent: [HabitCompletion] { Array(store.completions(for: current).prefix(8)) }
    private var tint: Color { HabitTint.color(for: current.colorIdentifier) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statistics
                if !current.details.isEmpty { notes }
                historyGrid
                recentActivity
                management
            }
            .padding()
        }
        .background(TenoraScreenBackground())
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { showingEditor = true } } }
        .sheet(isPresented: $showingEditor) { HabitEditorView(habit: current) }
        .confirmationDialog("Delete this habit and its check-in history?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete habit", role: .destructive) { Task { if await store.delete(current) { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.14))
                HabitArtworkView(iconName: current.iconName, size: 62, tint: tint, completed: store.isCompleted(current))
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(current.name).font(.title2.bold())
                Text(current.scheduleSummary).foregroundStyle(.secondary)
                if let reminder = current.reminderTimeText {
                    Label(reminder, systemImage: "bell.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(tint)
                }
            }
            Spacer()
            Button { Task { await store.toggleCompletion(current) } } label: {
                Image(systemName: store.isCompleted(current) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 34)).foregroundStyle(tint)
            }
            .accessibilityLabel(store.isCompleted(current) ? "Remove today's check-in" : "Check in today")
        }
        .padding(18).tenoraCard(cornerRadius: 20)
    }

    private var statistics: some View {
        let week = store.thisWeekSummary(for: current)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            stat("Last 30 days", value: store.completionRate(for: current, lastDays: 30).formatted(.percent.precision(.fractionLength(0))), symbol: "chart.bar.fill")
            stat("This week", value: week.scheduled == 0 ? "—" : "\(week.completed) / \(week.scheduled)", symbol: "calendar")
            stat("Total check-ins", value: "\(store.completions(for: current).count)", symbol: "checkmark.circle.fill")
            stat("Active days", value: "\(week.activeDays) this week", symbol: "circle.grid.2x2.fill")
        }
    }

    private func stat(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(Color.tenoraCopper)
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(15).tenoraCard(cornerRadius: 16)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("NOTES")
            Text(current.details).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).tenoraCard(cornerRadius: 18)
    }

    private var historyGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("LAST 6 WEEKS")
                Spacer()
                Text("Tap a day to correct it").font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(historyDates, id: \.self) { date in
                    historyDay(date)
                }
            }

            HStack(spacing: 14) {
                legend("Checked in", color: tint)
                legend("Scheduled", color: Color.tenoraSage.opacity(0.22), outlined: true)
                legend("Not scheduled", color: .clear, outlined: true)
            }
        }
        .padding(16).tenoraCard(cornerRadius: 18)
    }

    private func historyDay(_ date: Date) -> some View {
        let complete = store.isCompleted(current, on: date)
        let scheduled = HabitTrackingEngine().scheduleCalculator.isScheduled(current, on: date, completions: store.completions, calendar: calendar)
        let future = date > calendar.startOfDay(for: store.today)
        let beforeCreation = date < calendar.startOfDay(for: current.createdAt)
        return Button {
            Task { await store.toggleCompletion(current, on: date) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(complete ? tint : scheduled ? Color.tenoraSage.opacity(0.18) : Color.clear)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(scheduled ? tint.opacity(0.24) : Color.tenoraSage.opacity(0.18), lineWidth: 1)
                if complete { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) }
                else { Text("\(calendar.component(.day, from: date))").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
            }
            .aspectRatio(1, contentMode: .fit)
            .opacity(future || beforeCreation ? 0.28 : 1)
        }
        .buttonStyle(.plain)
        .disabled(future || beforeCreation)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(complete ? "checked in" : scheduled ? "scheduled, not checked in" : "not scheduled")")
    }

    private func legend(_ text: String, color: Color, outlined: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(outlined ? Color.tenoraSage.opacity(0.4) : Color.clear) }
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var historyDates: [Date] {
        let today = calendar.startOfDay(for: store.today)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -35, to: currentWeekStart) ?? currentWeekStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<symbols.count).map { symbols[($0 + calendar.firstWeekday - 1) % symbols.count] }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("RECENT CHECK-INS")
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, completion in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                            Text(completion.completionDate.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Button("Remove") { Task { await store.toggleCompletion(current, on: completion.completionDate) } }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 11)
                        if index < recent.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal).tenoraCard(cornerRadius: 16)
            }
        }
    }

    private var management: some View {
        VStack(spacing: 10) {
            Button("Archive Habit") { Task { if await store.archive(current) { dismiss() } } }
                .buttonStyle(TenoraSecondaryButtonStyle())
            Button("Delete Habit", role: .destructive) { showingDelete = true }
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
    }
}

extension Habit {
    var scheduleSummary: String {
        switch schedule.type {
        case .everyDay: return "Every day"
        case .specificWeekdays:
            let calendar = Calendar.current
            let names = (0..<calendar.shortWeekdaySymbols.count).compactMap { offset -> String? in
                let value = (offset + calendar.firstWeekday - 1) % calendar.shortWeekdaySymbols.count + 1
                return schedule.weekdays.contains(value) ? calendar.shortWeekdaySymbols[value - 1] : nil
            }
            return names.joined(separator: ", ")
        case .timesPerWeek: return "\(schedule.weeklyTarget) times per week"
        case .custom: return "Every \(schedule.intervalDays) days"
        }
    }

    var reminderTimeText: String? {
        guard let reminderMinute else { return nil }
        let date = Calendar.current.date(from: DateComponents(hour: reminderMinute / 60, minute: reminderMinute % 60)) ?? Date()
        return "Reminder at \(date.formatted(date: .omitted, time: .shortened))"
    }
}
