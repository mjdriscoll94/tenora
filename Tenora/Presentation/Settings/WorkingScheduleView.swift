import SwiftUI

struct WorkingScheduleView: View {
    @AppStorage(AttentionPreferences.scheduleKey) private var savedSchedule = ""
    @State private var schedule: WorkingSchedule
    private var weekdays: [Int] { (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 } }

    init() { _schedule = State(initialValue: AttentionPreferences.schedule) }

    var body: some View {
        List {
            Section {
                ForEach(weekdays, id: \.self) { weekday in
                    let day = schedule.day(weekday)
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
        }.navigationTitle("Weekly schedule")
    }

    private func binding(for weekday: Int) -> Binding<WorkDay> {
        Binding(get: { schedule.day(weekday) }, set: { day in
            guard let index = schedule.days.firstIndex(where: { $0.weekday == weekday }), day.isValid else { return }
            var updated = schedule
            updated.days[index] = day
            schedule = updated
            guard let data = try? JSONEncoder().encode(updated), let text = String(data: data, encoding: .utf8) else { return }
            savedSchedule = text
        })
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
                    DatePicker("End", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                } footer: {
                    Text(day.endMinute % 1440 == day.startMinute ? "These times cover a full 24 hours, ending the next day." : day.endsNextDay ? "This shift ends the next day." : "This shift starts and ends on the same day.")
                }
            } else {
                Text("No shift starts on this day. Your saved times will be kept if you mark it as working again.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Calendar.current.weekdaySymbols[day.weekday - 1])
    }

    private func timeBinding(_ keyPath: WritableKeyPath<WorkDay, Int>) -> Binding<Date> {
        Binding(get: { Self.timeDate(day[keyPath: keyPath]) }, set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            day[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        })
    }

    static func timeDate(_ minutes: Int) -> Date {
        // A stable winter date keeps the time editor independent of today's DST transition.
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: (minutes % 1440) / 60, minute: minutes % 60)) ?? Date()
    }
}
