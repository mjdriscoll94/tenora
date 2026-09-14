import SwiftUI
import UIKit

struct CalendarView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var calendarStore: CalendarStore
    @EnvironmentObject private var transitionStore: TransitionStore

    var body: some View {
        Group {
            switch calendarStore.authorization {
            case .notDetermined:
                permissionView
            case .fullAccess:
                eventList
            case .writeOnly, .denied, .restricted:
                unavailableView
            }
        }
        .background(Color.tenoraSurface.ignoresSafeArea())
        .navigationTitle("Calendar")
        .task { await calendarStore.refresh() }
        .refreshable { await calendarStore.refresh() }
        .overlay(alignment: .bottom) {
            if let errorMessage = calendarStore.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Connect your calendar", systemImage: "calendar.badge.plus")
        } description: {
            Text("Tenora uses your schedule to show what’s coming and find space for tasks. Calendar data stays on this device.")
        } actions: {
            Button("Allow Calendar Access") {
                Task { await calendarStore.requestAccess() }
            }
            .buttonStyle(TenoraPrimaryButtonStyle())
            .disabled(calendarStore.isRequestingAccess)
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Calendar access is off", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Allow full calendar access in Settings to see your schedule and available time.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var eventList: some View {
        if calendarStore.upcomingEvents.isEmpty {
            ContentUnavailableView(
                "Your day is open",
                systemImage: "calendar",
                description: Text("No remaining calendar events today.")
            )
        } else {
            List(calendarStore.upcomingEvents) { event in
                Group {
                    if event.isAllDay {
                        eventRow(event)
                    } else {
                        NavigationLink {
                            TransitionPlanView(event: event, existing: transitionStore.plan(for: event))
                        } label: { eventRow(event) }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(TenoraTheme.accentGradient)
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(eventTime(event)).font(.subheadline).foregroundStyle(.secondary)
                if !event.calendarName.isEmpty { Text(event.calendarName).font(.caption).foregroundStyle(.secondary) }
                if transitionStore.plan(for: event) != nil {
                    Label("Transition ready", systemImage: "figure.walk.departure")
                        .font(.caption).foregroundStyle(Color.tenoraBlue)
                }
            }
        }
    }

    private func eventTime(_ event: CalendarEvent) -> String {
        let today = Calendar.current.isDate(event.startDate, inSameDayAs: calendarStore.currentDate)
        if event.isAllDay { return today ? "All day" : "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) · All day" }
        return "\(event.startDate.formatted(date: today ? .omitted : .abbreviated, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
