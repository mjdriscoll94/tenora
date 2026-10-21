import Foundation

@MainActor
final class TransitionStore: ObservableObject {
    @Published private(set) var plans: [TransitionPlan] = []
    private let repository: TransitionRepository
    var didChange: (([TransitionPlan]) async -> Void)?

    init(repository: TransitionRepository) {
        self.repository = repository
        plans = repository.fetchTransitionPlans()
    }

    convenience init(defaults: UserDefaults = .standard) {
        let settings = UserDefaultsSettingsRepository(profileID: .offline, defaults: defaults)
        self.init(repository: UserDefaultsTransitionRepository(settings: settings))
    }

    func plan(for event: CalendarEvent) -> TransitionPlan? {
        plans.first { $0.eventID == event.externalIdentifier }
    }

    func save(_ plan: TransitionPlan) async {
        plans.removeAll { $0.eventID == plan.eventID }
        plans.append(plan)
        persist()
        await didChange?(plans)
    }

    func remove(eventID: String) async {
        plans.removeAll { $0.eventID == eventID }
        persist()
        await didChange?(plans)
    }

    func removeAll() async {
        plans = []
        persist()
        await didChange?(plans)
    }

    func replaceAll(_ restoredPlans: [TransitionPlan]) async {
        plans = restoredPlans
        persist()
        await didChange?(plans)
    }

    func synchronize(events: [CalendarEvent], now: Date = Date()) async {
        let byID = Dictionary(events.map { ($0.externalIdentifier, $0) }, uniquingKeysWith: { _, newest in newest })
        plans = plans.compactMap { plan in
            if plan.eventStart < now.addingTimeInterval(-86_400) { return nil }
            guard let event = byID[plan.eventID] else { return plan }
            var updated = plan
            updated.eventTitle = event.title
            updated.eventStart = event.startDate
            return updated
        }
        persist()
        await didChange?(plans)
    }

    private func persist() {
        try? repository.replaceTransitionPlans(plans)
    }
}
