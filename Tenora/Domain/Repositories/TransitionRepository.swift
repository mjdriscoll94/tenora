import Foundation

@MainActor
protocol TransitionRepository {
    func fetchTransitionPlans() -> [TransitionPlan]
    func replaceTransitionPlans(_ plans: [TransitionPlan]) throws
}
