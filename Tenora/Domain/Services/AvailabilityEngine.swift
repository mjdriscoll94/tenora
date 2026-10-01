import Foundation

struct WorkingHours: Equatable, Sendable {
    let startHour: Int
    let endHour: Int

    init(startHour: Int = 8, endHour: Int = 18) {
        precondition((0...23).contains(startHour))
        precondition((1...24).contains(endHour))
        precondition(startHour < endHour)
        self.startHour = startHour
        self.endHour = endHour
    }
}

struct FreeTimeWindow: Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    var durationMinutes: Int {
        max(0, Int(endDate.timeIntervalSince(startDate) / 60))
    }
}

struct AvailabilitySnapshot: Equatable, Sendable {
    let currentEvent: CalendarEvent?
    let nextEvent: CalendarEvent?
    let minutesUntilNextEvent: Int?
    let availableMinutes: Int?
    let freeTimeWindows: [FreeTimeWindow]
}

struct AvailabilityEngine: Sendable {
    func snapshot(
        at now: Date,
        events: [CalendarEvent],
        workingHours: WorkingHours = WorkingHours(),
        calendar: Calendar = .current,
        schedule: WorkingSchedule? = nil,
        meetingBufferMinutes: Int = 0,
        minimumGapMinutes: Int = 0
    ) -> AvailabilitySnapshot {
        let workIntervals = schedule?.intervals(around: now, calendar: calendar) ?? [workingInterval(
            containing: now,
            hours: workingHours,
            calendar: calendar
        )]
        let timedBusyEvents = events
            .filter { !$0.isAllDay && $0.isBusy && $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }

        let buffer = TimeInterval(max(0, meetingBufferMinutes) * 60)
        let bufferedBusyEvents = timedBusyEvents.map { event in
            CalendarEvent(
                externalIdentifier: event.externalIdentifier,
                title: event.title,
                startDate: event.startDate.addingTimeInterval(-buffer),
                endDate: event.endDate.addingTimeInterval(buffer),
                isAllDay: false,
                calendarName: event.calendarName,
                calendarIdentifier: event.calendarIdentifier,
                isBusy: true
            )
        }

        let currentEvent = timedBusyEvents.first {
            $0.startDate <= now && now < $0.endDate
        }
        let nextEvent = timedBusyEvents.first { $0.startDate > now }
        let minutesUntilNextEvent = nextEvent.map {
            max(0, Int($0.startDate.timeIntervalSince(now) / 60))
        }
        let freeWindows = workIntervals.flatMap { freeTimeWindows(
            within: $0,
            busyEvents: bufferedBusyEvents
        ) }.filter { $0.durationMinutes >= max(0, minimumGapMinutes) }

        let availableMinutes: Int?
        if let interval = workIntervals.first(where: { $0.start <= now && now < $0.end }) {
            if bufferedBusyEvents.contains(where: { $0.startDate <= now && now < $0.endDate }) { availableMinutes = 0 }
            else {
                let gapEnd = bufferedBusyEvents.first { $0.startDate > now && $0.startDate < interval.end }?.startDate ?? interval.end
                let minutes = max(0, Int(gapEnd.timeIntervalSince(now) / 60))
                availableMinutes = minutes >= max(0, minimumGapMinutes) ? minutes : 0
            }
        } else { availableMinutes = nil }

        return AvailabilitySnapshot(
            currentEvent: currentEvent,
            nextEvent: nextEvent,
            minutesUntilNextEvent: minutesUntilNextEvent,
            availableMinutes: availableMinutes,
            freeTimeWindows: freeWindows
        )
    }

    private func workingInterval(
        containing date: Date,
        hours: WorkingHours,
        calendar: Calendar
    ) -> DateInterval {
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(
            bySettingHour: hours.startHour,
            minute: 0,
            second: 0,
            of: dayStart
        ) ?? dayStart
        let end: Date
        if hours.endHour == 24 {
            end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            end = calendar.date(
                bySettingHour: hours.endHour,
                minute: 0,
                second: 0,
                of: dayStart
            ) ?? dayStart
        }
        return DateInterval(start: start, end: end)
    }

    private func freeTimeWindows(
        within workingInterval: DateInterval,
        busyEvents: [CalendarEvent]
    ) -> [FreeTimeWindow] {
        var result: [FreeTimeWindow] = []
        var cursor = workingInterval.start

        for event in busyEvents {
            let busyStart = max(event.startDate, workingInterval.start)
            let busyEnd = min(event.endDate, workingInterval.end)
            guard busyEnd > workingInterval.start,
                  busyStart < workingInterval.end,
                  busyEnd > cursor else { continue }

            if busyStart > cursor {
                result.append(FreeTimeWindow(startDate: cursor, endDate: busyStart))
            }
            cursor = max(cursor, busyEnd)
        }

        if cursor < workingInterval.end {
            result.append(FreeTimeWindow(startDate: cursor, endDate: workingInterval.end))
        }
        return result
    }
}
