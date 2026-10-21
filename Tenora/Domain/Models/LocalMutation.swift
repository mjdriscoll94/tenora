import Foundation

struct LocalMutation: Identifiable, Codable, Equatable, Sendable {
    enum Entity: String, Codable, Sendable {
        case task, habit, habitCompletion, transitionPlan
    }

    enum Operation: String, Codable, Sendable {
        case upsert, delete
    }

    let id: UUID
    let profileID: LocalProfileID
    let entity: Entity
    let recordID: String
    let operation: Operation
    let createdAt: Date
    let payload: Data?

    init(
        id: UUID = UUID(),
        profileID: LocalProfileID,
        entity: Entity,
        recordID: String,
        operation: Operation,
        createdAt: Date = Date(),
        payload: Data? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.entity = entity
        self.recordID = recordID
        self.operation = operation
        self.createdAt = createdAt
        self.payload = payload
    }
}
