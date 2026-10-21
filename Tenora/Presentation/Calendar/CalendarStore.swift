import Foundation

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var authorization: CalendarAuthorization
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var availableCalendars: [UserCalendar] = []
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var errorMessage: String?

    private let repository: any CalendarRepository
    private let availabilityEngine: AvailabilityEngine
    private let clock: any TenoraClock
    private let calendar: Calendar
    private let workingHoursOverride: WorkingHours?
    private let settings: SettingsRepository?
    private var loadedDay: Date?
    var didChange: (() -> Void)?

    init(
        repository: any CalendarRepository,
        availabilityEngine: AvailabilityEngine = AvailabilityEngine(),
        clock: any TenoraClock = SystemClock(),
        calendar: Calendar = .autoupdatingCurrent,
        workingHours: WorkingHours? = nil,
        settings: SettingsRepository? = nil
    ) {
        self.repository = repository
        self.availabilityEngine = availabilityEngine
        self.clock = clock
        self.calendar = calendar
        self.workingHoursOverride = workingHours
        self.settings = settings
        authorization = repository.authorizationStatus()
    }

    var currentDate: Date { clock.now }

    var availability: AvailabilitySnapshot? {
        guard authorization == .fullAccess, errorMessage == nil,
              loadedDay == calendar.startOfDay(for: clock.now) else { return nil }
        return availabilityEngine.snapshot(
            at: clock.now,
            events: events,
            workingHours: workingHoursOverride ?? preferredWorkingHours,
            calendar: calendar,
            schedule: workingHoursOverride == nil ? preferredSchedule : nil,
            meetingBufferMinutes: settings?.integer(for: .meetingBufferMinutes, default: 0) ?? AttentionPreferences.meetingBufferMinutes,
            minimumGapMinutes: settings?.integer(for: .minimumGapMinutes, default: 15) ?? AttentionPreferences.minimumGapMinutes
        )
    }

    var upcomingEvents: [CalendarEvent] {
        events
            .filter { $0.isAllDay || $0.endDate > clock.now }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
    }

    func refresh() async {
        defer { didChange?() }
        authorization = repository.authorizationStatus()
        guard authorization == .fullAccess else {
            events = []
            availableCalendars = []
            loadedDay = nil
            errorMessage = nil
            return
        }
        await loadTodayEvents()
    }

    func requestAccess() async {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false; didChange?() }

        do {
            authorization = try await repository.requestAccess()
            if authorization == .fullAccess {
                await loadTodayEvents()
            }
        } catch {
            authorization = repository.authorizationStatus()
            errorMessage = "Tenora couldn't connect to your calendar."
        }
    }

    private func loadTodayEvents() async {
        let dayStart = calendar.startOfDay(for: clock.now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        // An evening shift can need tomorrow's events before midnight arrives.
        let shiftEnd = workingHoursOverride == nil ? preferredSchedule.intervals(around: clock.now, calendar: calendar).map(\.end).max() : nil
        let horizonEnd = max(dayEnd, shiftEnd ?? dayEnd)

        do {
            availableCalendars = try await repository.calendars()
            let fetchedEvents = try await repository.events(in: DateInterval(start: dayStart, end: horizonEnd))
            if settings?.bool(for: .useAllCalendars, default: true) ?? AttentionPreferences.useAllCalendars {
                events = fetchedEvents
            } else {
                let selected = preferredCalendarIDs
                events = fetchedEvents.filter { event in
                    guard let identifier = event.calendarIdentifier else { return false }
                    return selected.contains(identifier)
                }
            }
            loadedDay = dayStart
            errorMessage = nil
        } catch {
            events = []
            loadedDay = nil
            errorMessage = "Tenora couldn't load today's events."
        }
    }

    private var preferredWorkingHours: WorkingHours {
        guard let settings else { return AttentionPreferences.workingHours }
        return WorkingHours(
            startHour: settings.integer(for: .legacyWorkStart, default: 8),
            endHour: settings.integer(for: .legacyWorkEnd, default: 18)
        )
    }

    private var preferredSchedule: WorkingSchedule {
        guard let settings else { return AttentionPreferences.schedule }
        return AttentionPreferences.schedule(
            from: settings.string(for: .workingSchedule) ?? "",
            fallback: preferredWorkingHours
        )
    }

    private var preferredCalendarIDs: Set<String> {
        guard let data = settings?.data(for: .selectedCalendarIDs),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return AttentionPreferences.selectedCalendarIDs
        }
        return Set(values)
    }
}
