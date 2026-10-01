import SwiftUI
import UIKit

struct HabitDashboardView: View {
    @EnvironmentObject private var store: HabitStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("habits.intro.seen") private var hasSeenIntro = false
    @State private var showingEditor = false
    @State private var showingIntro = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                playerWorldSection

                if store.activeHabits.isEmpty { emptyState }
                else {
                    quests
                    NavigationLink { HabitWeeklyView() } label: { dashboardLink("Weekly view", detail: weeklyDetail, symbol: "calendar") }
                    NavigationLink { HabitCollectionView() } label: { dashboardLink("Your collection", detail: "World upgrades and achievements", symbol: "square.grid.2x2.fill") }
                }
            }
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
        .overlay { celebrationOverlay }
        .task {
            await store.load()
            if !hasSeenIntro && store.activeHabits.isEmpty { showingIntro = true }
        }
    }

    private var playerWorldSection: some View {
        VStack(spacing: 0) {
            playerHeader
            Color.tenoraSurface
                .frame(height: 18)
                .zIndex(1)
                .accessibilityHidden(true)
            HabitWorldView(
                unlockedRewardIDs: store.rewardIDs,
                compact: store.activeHabits.isEmpty
            )
        }
    }

    private var playerHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LEVEL \(store.progress.level)")
                        .font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(Color.tenoraSage)
                    Text("Keep building")
                        .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                Label("\(store.progress.currentMomentum)", systemImage: "flame.fill")
                    .font(.headline).foregroundStyle(Color.tenoraSage)
                    .accessibilityLabel("Momentum \(store.progress.currentMomentum) days")
            }
            ProgressView(value: Double(store.progress.xpIntoLevel), total: Double(max(1, store.progress.xpForNextLevel)))
                .tint(Color.tenoraCopper)
            HStack {
                Text("\(store.progress.xpIntoLevel) / \(store.progress.xpForNextLevel) XP")
                Spacer()
                Text("TODAY  \(store.todaySummary.completed) / \(store.todaySummary.scheduled) QUESTS")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.78))
        }
        .padding(20)
        .background(TenoraNowCardBackground())
        .accessibilityElement(children: .combine)
    }

    private var quests: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY'S QUESTS").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(Color.tenoraCopper)
                Spacer()
                if store.todaySummary.scheduled > 0, !store.todaySummary.keepsMomentum {
                    Text(momentumPrompt).font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.todayHabits.isEmpty {
                Text("No quests are scheduled today. Your progress is still here when you return.")
                    .font(.subheadline).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity).tenoraCard()
            } else {
                ForEach(store.todayHabits) { habit in
                    HabitQuestCard(habit: habit)
                }
            }
        }
    }

    private var momentumPrompt: String {
        let needed = max(0, Int(ceil(Double(store.todaySummary.scheduled) * 0.5)) - store.todaySummary.completed)
        return needed == 1 ? "One more keeps Momentum going" : "\(needed) more keep Momentum going"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 40)).foregroundStyle(TenoraTheme.accentGradient)
            Text("Build Your First Routine").font(.title2.bold())
            Text("Create a habit and each completion will build your progress over time.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showingEditor = true } label: {
                Text("Create Habit").frame(maxWidth: .infinity)
            }
            .buttonStyle(TenoraPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(24).tenoraCard(cornerRadius: 22)
    }

    private var weeklyDetail: String {
        let days = store.weeklySummary()
        let scheduled = days.reduce(0) { $0 + $1.scheduled }
        let complete = days.reduce(0) { $0 + $1.completed }
        return scheduled == 0 ? "Your week at a glance" : "\(Int((Double(complete) / Double(scheduled)) * 100))% complete this week"
    }

    private func dashboardLink(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.tenoraCopper).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        .padding(16).contentShape(Rectangle()).tenoraCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let celebration = store.celebration {
            VStack(spacing: 12) {
                Image(systemName: celebration.symbol)
                    .font(.system(size: celebration.kind == .levelUp ? 44 : 30, weight: .bold))
                    .foregroundStyle(TenoraTheme.accentGradient)
                Text(celebration.title).font(.title2.bold())
                Text(celebration.detail).foregroundStyle(.secondary)
                Button("Continue") { store.celebration = nil }.buttonStyle(TenoraPrimaryButtonStyle())
            }
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
            .padding(30)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .onAppear {
                let generator = celebration.kind == .completion ? UIImpactFeedbackGenerator(style: .light) : UINotificationFeedbackGenerator()
                if let impact = generator as? UIImpactFeedbackGenerator { impact.impactOccurred() }
                else { (generator as? UINotificationFeedbackGenerator)?.notificationOccurred(.success) }
                if celebration.kind == .completion {
                    Task { try? await Task.sleep(for: .seconds(1.2)); if store.celebration?.id == celebration.id { store.celebration = nil } }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: celebration.id)
        }
    }
}

private struct HabitQuestCard: View {
    @EnvironmentObject private var store: HabitStore
    let habit: Habit

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(HabitTint.color(for: habit.colorIdentifier).opacity(0.16)).frame(width: 50, height: 50)
                Image(systemName: store.isCompleted(habit) ? "checkmark" : habit.iconName)
                    .font(.title3.weight(.semibold)).foregroundStyle(HabitTint.color(for: habit.colorIdentifier))
            }
            NavigationLink { HabitDetailView(habit: habit) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name).font(.headline).foregroundStyle(.primary).strikethrough(store.isCompleted(habit))
                    HStack(spacing: 10) {
                        Text("\(HabitGameEngine().xpAward(for: habit.difficulty)) XP")
                        Text("Momentum: \(store.currentMomentum(for: habit))")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await store.toggleCompletion(habit) }
            } label: {
                Image(systemName: store.isCompleted(habit) ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(HabitTint.color(for: habit.colorIdentifier))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isCompleted(habit) ? "Undo completion for \(habit.name)" : "Complete \(habit.name)")
        }
        .padding(16).tenoraCard(cornerRadius: 18)
        .accessibilityAction(named: store.isCompleted(habit) ? "Undo" : "Complete") { Task { await store.toggleCompletion(habit) } }
    }
}

private struct HabitIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    let onCreate: () -> Void
    private let pages = [
        ("sparkles", "Small steps earn XP", "Every completion adds to progress that stays with you."),
        ("flame.fill", "Consistency builds Momentum", "Half of today's quests keeps Momentum moving—perfection isn't required."),
        ("leaf.fill", "Your world grows", "Levels unlock a quiet landscape that never shrinks when you miss a day.")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(spacing: 20) {
                            Image(systemName: pages[index].0).font(.system(size: 56)).foregroundStyle(TenoraTheme.accentGradient)
                            Text(pages[index].1).font(.title.bold()).multilineTextAlignment(.center)
                            Text(pages[index].2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(30).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .always))
                Button(page == pages.count - 1 ? "Create Your First Habit" : "Continue") {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { onCreate() }
                }.buttonStyle(TenoraPrimaryButtonStyle())
                Button("Not now") { dismiss() }.foregroundStyle(.secondary)
            }
            .padding().background(TenoraScreenBackground()).navigationTitle("How Habits Work").navigationBarTitleDisplayMode(.inline)
        }
    }
}

#if DEBUG
#Preview("Empty") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.empty))
}
#Preview("New player") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.newPlayer))
}
#Preview("Partially complete") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.partial))
}
#Preview("Perfect day") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.perfect))
}
#Preview("High-level player") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.highLevel))
}
#Preview("Dark mode") {
    NavigationStack { HabitDashboardView() }.environmentObject(HabitStore.preview(.partial)).preferredColorScheme(.dark)
}
#Preview("Large Dynamic Type") {
    NavigationStack { HabitDashboardView() }
        .environmentObject(HabitStore.preview(.partial))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
