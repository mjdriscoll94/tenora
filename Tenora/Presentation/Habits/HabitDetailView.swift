import SwiftUI

struct HabitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HabitStore
    let habit: Habit
    @State private var showingEditor = false
    @State private var showingDelete = false

    private var current: Habit { store.habits.first(where: { $0.id == habit.id }) ?? habit }
    private var recent: [HabitCompletion] { Array(store.completions(for: current).prefix(10)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statistics
                historyGrid
                recentActivity
                management
            }.padding()
        }
        .background(TenoraScreenBackground())
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { showingEditor = true } } }
        .sheet(isPresented: $showingEditor) { HabitEditorView(habit: current) }
        .confirmationDialog("Delete this habit and its history?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Delete habit", role: .destructive) { Task { if await store.delete(current) { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HabitTint.color(for: current.colorIdentifier).opacity(0.16)).frame(width: 68, height: 68)
                HabitArtworkView(iconName: current.iconName, size: 64, tint: HabitTint.color(for: current.colorIdentifier))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(current.name).font(.title2.bold())
                Text(current.scheduleSummary).foregroundStyle(.secondary)
                Text("\(HabitGameEngine().xpAward(for: current.difficulty)) XP · \(current.difficulty.title)")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.tenoraCopper)
            }
            Spacer()
            Button { Task { await store.toggleCompletion(current) } } label: {
                Image(systemName: store.isCompleted(current) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32)).foregroundStyle(HabitTint.color(for: current.colorIdentifier))
            }.accessibilityLabel(store.isCompleted(current) ? "Undo today's completion" : "Complete today")
        }
        .padding(18).tenoraCard(cornerRadius: 20)
    }

    private var statistics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            stat("Momentum", value: "\(store.currentMomentum(for: current)) days", symbol: "flame.fill")
            stat("Completions", value: "\(store.completions(for: current).count)", symbol: "checkmark.circle.fill")
            stat("Completion rate", value: store.completionRate(for: current).formatted(.percent.precision(.fractionLength(0))), symbol: "chart.line.uptrend.xyaxis")
            stat("XP earned", value: "\(store.xpEarned(for: current)) XP", symbol: "sparkles")
        }
    }

    private func stat(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(Color.tenoraCopper)
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15).tenoraCard(cornerRadius: 16)
    }

    private var historyGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT HISTORY").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 14), spacing: 5) {
                ForEach(historyDates, id: \.self) { date in
                    let complete = store.isCompleted(current, on: date)
                    let scheduled = HabitGameEngine().scheduleCalculator.isScheduled(current, on: date, completions: store.completions, calendar: .autoupdatingCurrent)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(complete ? HabitTint.color(for: current.colorIdentifier) : scheduled ? Color.tenoraSage.opacity(0.20) : Color.clear)
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(scheduled ? Color.tenoraSage.opacity(0.32) : Color.clear, lineWidth: 1) }
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted)), \(complete ? "complete" : scheduled ? "not complete" : "not scheduled")")
                }
            }
            Text("The last 12 weeks · filled squares are completed quests")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(16).tenoraCard(cornerRadius: 18)
    }

    private var historyDates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<84).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 83, to: today) }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECENT ACTIVITY").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, completion in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.tenoraForest)
                            VStack(alignment: .leading) {
                                Text(completion.completionDate.formatted(date: .abbreviated, time: .omitted))
                                Text("+\(completion.xpAwarded) XP").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Undo") { Task { await store.toggleCompletion(current, on: completion.completionDate) } }
                                .font(.caption.weight(.semibold))
                        }.padding(.vertical, 11)
                        if index < recent.count - 1 { Divider() }
                    }
                }.padding(.horizontal).tenoraCard(cornerRadius: 16)
            }
        }
    }

    private var management: some View {
        VStack(spacing: 10) {
            Button("Archive Habit") { Task { if await store.archive(current) { dismiss() } } }.buttonStyle(TenoraSecondaryButtonStyle())
            Button("Delete Habit", role: .destructive) { showingDelete = true }
        }.frame(maxWidth: .infinity)
    }
}

extension Habit {
    var scheduleSummary: String {
        switch schedule.type {
        case .everyDay: return "Every day"
        case .specificWeekdays:
            let names = schedule.weekdays.sorted().compactMap { value in
                Calendar.current.shortWeekdaySymbols.indices.contains(value - 1) ? Calendar.current.shortWeekdaySymbols[value - 1] : nil
            }
            return names.joined(separator: ", ")
        case .timesPerWeek: return "\(schedule.weeklyTarget) times per week"
        case .custom: return "Every \(schedule.intervalDays) days"
        }
    }
}
