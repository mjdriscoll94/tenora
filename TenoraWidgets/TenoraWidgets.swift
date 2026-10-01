import AppIntents
import SwiftUI
import WidgetKit

struct TenoraEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var task: TenoraTask? { snapshot?.recommendation(at: date) }
    var nextEvent: CalendarEvent? {
        guard let snapshot, date.timeIntervalSince(snapshot.updatedAt) < 6 * 3600 else { return nil }
        return snapshot.events.filter { !$0.isAllDay && $0.startDate > date }.min { $0.startDate < $1.startDate }
    }
    var url: URL { URL(string: task.map { "tenora://task/\($0.id)" } ?? "tenora://today")! }
}

struct TenoraProvider: TimelineProvider {
    func placeholder(in context: Context) -> TenoraEntry {
        .init(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TenoraEntry) -> Void) {
        completion(.init(date: Date(), snapshot: WidgetSnapshot.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TenoraEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.read()
        var dates = (0...24).map { now.addingTimeInterval(Double($0) * 900) }
        dates += (snapshot?.events ?? []).flatMap { [$0.startDate, $0.endDate] }.filter { $0 > now && $0 < now.addingTimeInterval(6 * 3600) }
        dates += (snapshot?.tasks ?? []).compactMap(\.nextSurfaceAt).filter { $0 > now && $0 < now.addingTimeInterval(6 * 3600) }
        dates += (snapshot?.tasks ?? []).compactMap(\.scheduledDate).filter { $0 > now && $0 < now.addingTimeInterval(6 * 3600) }
        if let schedule = snapshot?.schedule {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            dates += [now, tomorrow].flatMap { schedule.intervals(around: $0) }.flatMap { [$0.start, $0.end] }
                .filter { $0 > now && $0 < now.addingTimeInterval(6 * 3600) }
        }
        let entries = Set(dates).sorted().map { TenoraEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

struct TenoraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TenoraEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NOW").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.88, green: 0.63, blue: 0.50))
                Spacer()
                if family == .systemMedium {
                    Link(destination: URL(string: "tenora://add")!) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }.accessibilityLabel("Add task to Tenora")
                }
            }
            Link(destination: entry.url) {
                Text(entry.task?.title ?? "Open Tenora to find your next step")
                    .font(.headline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
            if family == .systemMedium, let step = entry.task?.nextStep, !step.isEmpty {
                Text("Next: \(step)").font(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
            if family == .systemMedium, let event = entry.nextEvent {
                Text("UP NEXT").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                Text("\(event.startDate.formatted(date: Calendar.current.isDate(event.startDate, inSameDayAs: entry.date) ? .omitted : .abbreviated, time: .shortened))  \(event.title)")
                    .font(.subheadline).lineLimit(1)
            }
            Text("TENORA").font(.caption2).tracking(2).foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .privacySensitive()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.078, green: 0.157, blue: 0.133), Color(red: 0.12, green: 0.25, blue: 0.21)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .widgetURL(entry.url)
    }
}

struct TenoraNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TenoraNow", provider: TenoraProvider()) { TenoraWidgetView(entry: $0) }
            .configurationDisplayName("Your next step")
            .description("Keep your next task and calendar event in view. Tap + to capture something.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CompleteHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Habit"
    static var description = IntentDescription("Completes a Tenora quest from the Habits widget.")
    static var openAppWhenRun = false

    @Parameter(title: "Habit ID") var habitID: String

    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        HabitWidgetSnapshot.queueCompletion(id: id)
        if var snapshot = HabitWidgetSnapshot.read(),
           let index = snapshot.quests.firstIndex(where: { $0.id == id && !$0.isCompleted }) {
            snapshot.quests[index].isCompleted = true
            snapshot.completedCount = snapshot.quests.filter(\.isCompleted).count
            snapshot.write()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "TenoraHabits")
        return .result()
    }
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: HabitWidgetSnapshot?
}

struct HabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: Date(), snapshot: HabitWidgetSnapshot(
            updatedAt: Date(),
            quests: [HabitWidgetQuest(id: UUID(), title: "Take one small step", iconName: "leaf.fill", xp: 10, isCompleted: false)],
            momentum: 3, level: 2, completedCount: 1, totalCount: 3
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(HabitEntry(date: Date(), snapshot: HabitWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [HabitEntry(date: now, snapshot: HabitWidgetSnapshot.read())], policy: .after(now.addingTimeInterval(900))))
    }
}

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitEntry

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY'S QUESTS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(Color(red: 0.72, green: 0.67, blue: 1.0))
                Spacer()
                Text("LV \(snapshot?.level ?? 1)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.72))
            }
            Text("\(snapshot?.completedCount ?? 0) / \(snapshot?.totalCount ?? 0)")
                .font(.title2.bold())
            ProgressView(value: Double(snapshot?.completedCount ?? 0), total: Double(max(1, snapshot?.totalCount ?? 0)))
                .tint(Color(red: 0.48, green: 0.36, blue: 1.0))
            if family == .systemMedium {
                VStack(spacing: 5) {
                    ForEach(Array((snapshot?.quests ?? []).prefix(4))) { quest in
                        HStack(spacing: 8) {
                            if quest.isCompleted {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.24, green: 0.68, blue: 0.94))
                            } else {
                                Button(intent: CompleteHabitIntent(habitID: quest.id)) {
                                    Image(systemName: "circle").foregroundStyle(.white.opacity(0.78))
                                }.buttonStyle(.plain).accessibilityLabel("Complete \(quest.title)")
                            }
                            Text(quest.title).font(.caption).lineLimit(1)
                            Spacer()
                            Text("\(quest.xp) XP").font(.caption2).foregroundStyle(.white.opacity(0.60))
                        }
                    }
                }
            } else if let quest = snapshot?.quests.first(where: { !$0.isCompleted }) {
                Button(intent: CompleteHabitIntent(habitID: quest.id)) {
                    Label(quest.title, systemImage: "circle").font(.caption).lineLimit(2)
                }.buttonStyle(.plain).accessibilityLabel("Complete \(quest.title)")
            } else {
                Text((snapshot?.totalCount ?? 0) == 0 ? "Open Tenora to create a habit" : "Every quest is complete")
                    .font(.caption).foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
            Label("Momentum \(snapshot?.momentum ?? 0)", systemImage: "flame.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.24), Color(red: 0.16, green: 0.12, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "tenora://habits"))
    }
}

struct TenoraHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TenoraHabits", provider: HabitProvider()) { HabitWidgetView(entry: $0) }
            .configurationDisplayName("Today's Quests")
            .description("See your habit progress and complete a quest in one tap.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TenoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        TenoraNowWidget()
        TenoraHabitsWidget()
    }
}
