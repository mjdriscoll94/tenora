import SwiftUI

struct WorkingScheduleView: View {
    @StateObject private var editor: WorkingScheduleEditor
    private var weekdays: [Int] { (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 } }

    init() { _editor = StateObject(wrappedValue: WorkingScheduleEditor()) }

    var body: some View {
        List {
            Section {
                ForEach(weekdays, id: \.self) { weekday in
                    let day = editor.schedule.day(weekday)
                    NavigationLink {
                        WorkDayView(day: binding(for: weekday))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).font(.headline)
                            Text(day.isEnabled ? "\(time(day.startMinute)) – \(time(day.endMinute))\(day.endsNextDay ? " · next day" : "")" : "Day off")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("workday-\(weekday)")
                }
            } footer: {
                Text("This schedule repeats weekly and saves automatically on this device. Times follow your local time zone. Overnight shifts belong to the day they start, so a day off can still include the end of the previous night's shift.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle("Weekly schedule")
    }

    private func binding(for weekday: Int) -> Binding<WorkDay> {
        Binding(
            get: { editor.schedule.day(weekday) },
            set: { _ = editor.update($0) }
        )
    }

    private func time(_ minutes: Int) -> String {
        WorkDayView.timeDate(minutes).formatted(date: .omitted, time: .shortened)
    }
}

private struct WorkDayView: View {
    @Binding var day: WorkDay

    var body: some View {
        Form {
            Section {
                Picker("Day status", selection: Binding(
                    get: { day.isEnabled },
                    set: { value in var updated = day; updated.isEnabled = value; day = updated }
                )) {
                    Text("Working").tag(true)
                    Text("Day off").tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("workday-status")
            }
            if day.isEnabled {
                Section {
                    DatePicker("Start", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("workday-start")
                    DatePicker("End", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("workday-end")
                } footer: {
                    Text(day.endMinute % 1440 == day.startMinute ? "These times cover a full 24 hours, ending the next day." : day.endsNextDay ? "This shift ends the next day." : "This shift starts and ends on the same day.")
                }
            } else {
                Text("No shift starts on this day. Your saved times will be kept if you mark it as working again.").foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(TenoraScreenBackground())
        .tint(.tenoraForest)
        .navigationTitle(Calendar.current.weekdaySymbols[day.weekday - 1])
    }

    private func timeBinding(_ keyPath: WritableKeyPath<WorkDay, Int>) -> Binding<Date> {
        Binding(get: { Self.timeDate(day[keyPath: keyPath]) }, set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            var updated = day
            updated[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            day = updated
        })
    }

    static func timeDate(_ minutes: Int) -> Date {
        // A stable winter date keeps the time editor independent of today's DST transition.
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: (minutes % 1440) / 60, minute: minutes % 60)) ?? Date()
    }
}

final class WorkingScheduleEditor: ObservableObject {
    @Published private(set) var schedule: WorkingSchedule

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        schedule = AttentionPreferences.schedule(
            from: defaults.string(forKey: AttentionPreferences.scheduleKey) ?? "",
            fallback: AttentionPreferences.workingHours(from: defaults)
        )
    }

    /// Replaces the complete day value before publishing it, ensuring nested controls
    /// cannot visually change without also reaching the persistence boundary.
    @discardableResult
    func update(_ day: WorkDay) -> Bool {
        guard day.isValid,
              let index = schedule.days.firstIndex(where: { $0.weekday == day.weekday }) else { return false }
        var updated = schedule
        updated.days[index] = day
        guard updated.isValid,
              let data = try? JSONEncoder().encode(updated),
              let json = String(data: data, encoding: .utf8) else { return false }
        defaults.set(json, forKey: AttentionPreferences.scheduleKey)
        schedule = updated
        return true
    }
}
