import Foundation

enum DayHorizonPhase: String, Sendable {
    case soon = "Soon"
    case later = "Later"
}

struct DayHorizonItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case task(UUID)
        case event(String)
        case wrapUp(String)
        case leave(String)
    }

    let kind: Kind
    let title: String
    let detail: String
    let date: Date
    let phase: DayHorizonPhase
    var id: String { "\(kind)-\(date.timeIntervalSinceReferenceDate)" }
}

struct DayHorizonEngine: Sendable {
    func items(tasks: [TenoraTask], events: [CalendarEvent], transitions: [TransitionPlan], now: Date, calendar: Calendar = .current) -> [DayHorizonItem] {
        let horizon = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        var result: [DayHorizonItem] = []

        for event in events where !event.isAllDay && event.startDate > now && event.startDate <= horizon {
            result.append(item(kind: .event(event.externalIdentifier), title: event.title, detail: event.calendarName, date: event.startDate, now: now))
        }
        for plan in transitions {
            if plan.wrapUpLeadMinutes > 0, plan.wrapUpAt > now, plan.wrapUpAt <= horizon {
                result.append(item(kind: .wrapUp(plan.eventID), title: "Wrap up", detail: "Before \(plan.eventTitle)", date: plan.wrapUpAt, now: now))
            }
            if plan.leaveAt > now, plan.leaveAt <= horizon {
                result.append(item(kind: .leave(plan.eventID), title: "Leave for \(plan.eventTitle)", detail: "Transition reminder", date: plan.leaveAt, now: now))
            }
        }
        for task in tasks where ![.completed, .archived, .waiting].contains(task.status) {
            let dates = [task.scheduledDate, task.dueDate, task.nextSurfaceAt].compactMap { $0 }.filter { $0 > now && $0 <= horizon }
            guard let date = dates.min() else { continue }
            result.append(item(kind: .task(task.id), title: task.title, detail: task.returnTrigger?.summary ?? "Task", date: date, now: now))
        }
        return result.sorted { $0.date < $1.date }
    }

    private func item(kind: DayHorizonItem.Kind, title: String, detail: String, date: Date, now: Date) -> DayHorizonItem {
        DayHorizonItem(kind: kind, title: title, detail: detail, date: date,
                       phase: date <= now.addingTimeInterval(3 * 3600) ? .soon : .later)
    }
}
