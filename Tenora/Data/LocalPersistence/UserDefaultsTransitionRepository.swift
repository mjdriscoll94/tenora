import Foundation

@MainActor
final class UserDefaultsTransitionRepository: TransitionRepository {
    private let settings: SettingsRepository
    private let outbox: MutationOutbox?

    init(settings: SettingsRepository, outbox: MutationOutbox? = nil) {
        self.settings = settings
        self.outbox = outbox
    }

    func fetchTransitionPlans() -> [TransitionPlan] {
        guard let data = settings.object(for: .transitionPlans) as? Data else { return [] }
        return (try? JSONDecoder().decode([TransitionPlan].self, from: data)) ?? []
    }

    func replaceTransitionPlans(_ plans: [TransitionPlan]) throws {
        let previous = fetchTransitionPlans()
        settings.set(try JSONEncoder().encode(plans), for: .transitionPlans)
        guard let outbox else { return }
        let currentIDs = Set(plans.map(\.id))
        for removed in previous where !currentIDs.contains(removed.id) {
            try outbox.enqueue(LocalMutation(
                profileID: settings.profileID,
                entity: .transitionPlan,
                recordID: removed.id,
                operation: .delete
            ))
        }
        for plan in plans {
            try outbox.enqueue(LocalMutation(
                profileID: settings.profileID,
                entity: .transitionPlan,
                recordID: plan.id,
                operation: .upsert,
                payload: try JSONEncoder().encode(plan)
            ))
        }
    }
}
