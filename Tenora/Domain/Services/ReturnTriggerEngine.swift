import Foundation

struct ReturnTriggerEngine: Sendable {
    func isReady(
        _ trigger: ReturnTrigger,
        tasks: [TenoraTask],
        events: [CalendarEvent],
        availability: AvailabilitySnapshot?,
        now: Date
    ) -> Bool {
        switch trigger {
        case .taskCompleted(let taskID, _):
            return tasks.first(where: { $0.id == taskID })?.status == .completed
        case .calendarEventEnded(let eventID, _, let fallbackEnd):
            let end = events.first(where: { $0.externalIdentifier == eventID })?.endDate ?? fallbackEnd
            return end <= now
        case .freeWindow(let minimumMinutes, _):
            return (availability?.availableMinutes ?? -1) >= minimumMinutes
        }
    }

    func nextCandidate(for trigger: ReturnTrigger, availability: AvailabilitySnapshot?, now: Date) -> Date? {
        switch trigger {
        case .taskCompleted: nil
        case .calendarEventEnded(_, _, let end): end
        case .freeWindow(let minimumMinutes, let existing):
            availability?.freeTimeWindows.first {
                $0.endDate > now && max($0.startDate, now).addingTimeInterval(TimeInterval(minimumMinutes * 60)) <= $0.endDate
            }.map { max($0.startDate, now) } ?? existing
        }
    }
}
