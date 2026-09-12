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
                Text("NOW").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.71, green: 0.62, blue: 1))
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
        .containerBackground(for: .widget) { Color(red: 0.059, green: 0.122, blue: 0.227) }
        .widgetURL(entry.url)
    }
}

@main
struct TenoraNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TenoraNow", provider: TenoraProvider()) { TenoraWidgetView(entry: $0) }
            .configurationDisplayName("Your next step")
            .description("Keep your next task and calendar event in view. Tap + to capture something.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
