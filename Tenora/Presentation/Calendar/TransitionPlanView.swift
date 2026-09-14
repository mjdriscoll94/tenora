import SwiftUI

struct TransitionPlanView: View {
    let event: CalendarEvent
    @EnvironmentObject private var store: TransitionStore
    @Environment(\.dismiss) private var dismiss
    @State private var leaveLead: Int
    @State private var wrapLead: Int

    init(event: CalendarEvent, existing: TransitionPlan?) {
        self.event = event
        _leaveLead = State(initialValue: existing?.leaveLeadMinutes ?? 15)
        _wrapLead = State(initialValue: existing?.wrapUpLeadMinutes ?? 10)
    }

    var body: some View {
        Form {
            Section {
                Text(event.title).font(.headline)
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            Section("Leave reminder") {
                Picker("Leave", selection: $leaveLead) {
                    Text("At start time").tag(0)
                    ForEach([5, 10, 15, 30, 45, 60], id: \.self) { Text("\($0) min before").tag($0) }
                }
            }
            Section("Wrap-up reminder") {
                Picker("Wrap up", selection: $wrapLead) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before leaving").tag($0) }
                }
                Text("Tenora can give you a gentle boundary before it is time to leave.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.plan(for: event) != nil {
                Section { Button("Turn off transition reminders", role: .destructive) { Task { await store.remove(eventID: event.externalIdentifier); dismiss() } } }
            }
        }
        .navigationTitle("Event Transition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await store.save(TransitionPlan(eventID: event.externalIdentifier, eventTitle: event.title,
                                                        eventStart: event.startDate, leaveLeadMinutes: leaveLead,
                                                        wrapUpLeadMinutes: wrapLead))
                        dismiss()
                    }
                }
            }
        }
    }
}
