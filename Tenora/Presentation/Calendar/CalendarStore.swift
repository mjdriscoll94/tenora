import Foundation

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var authorization: CalendarAuthorization
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var errorMessage: String?

    private let repository: any CalendarRepository
    private let availabilityEngine: AvailabilityEngine
    private let clock: any TenoraClock
    private let calendar: Calendar
    private let workingHoursOverride: WorkingHours?
    private var loadedDay: Date?
    var didChange: (() -> Void)?

    init(
        repository: any CalendarRepository,
        availabilityEngine: AvailabilityEngine = AvailabilityEngine(),
        clock: any TenoraClock = SystemClock(),
        calendar: Calendar = .autoupdatingCurrent,
        workingHours: WorkingHours? = nil
    ) {
        self.repository = repository
        self.availabilityEngine = availabilityEngine
        self.clock = clock
        self.calendar = calendar
        self.workingHoursOverride = workingHours
        authorization = repository.authorizationStatus()
    }

    var currentDate: Date { clock.now }

    var availability: AvailabilitySnapshot? {
        guard authorization == .fullAccess, errorMessage == nil,
              loadedDay == calendar.startOfDay(for: clock.now) else { return nil }
        return availabilityEngine.snapshot(
            at: clock.now,
            events: events,
            workingHours: workingHoursOverride ?? AttentionPreferences.workingHours,
            calendar: calendar
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

        do {
            events = try await repository.events(in: DateInterval(start: dayStart, end: dayEnd))
            loadedDay = dayStart
            errorMessage = nil
        } catch {
            events = []
            loadedDay = nil
            errorMessage = "Tenora couldn't load today's events."
        }
    }
}
