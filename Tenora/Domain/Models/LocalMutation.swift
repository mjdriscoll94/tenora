import Foundation

struct LocalMutation: Identifiable, Codable, Equatable, Sendable {
    enum Entity: String, Codable, Sendable {
        case task, habit, habitCompletion, transitionPlan
    }

    enum Operation: String, Codable, Sendable {
        case upsert, delete
    }

    enum State: String, Codable, Sendable {
        case pending
        case retryScheduled
        case blocked
    }

    let id: UUID
    let profileID: LocalProfileID
    let entity: Entity
    let recordID: String
    let operation: Operation
    let createdAt: Date
    let payload: Data?
    let baseServerVersion: Int64?
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextAttemptAt: Date?
    var state: State
    var lastFailureCode: String?

    var idempotencyKey: String { id.uuidString.lowercased() }

    init(
        id: UUID = UUID(),
        profileID: LocalProfileID,
        entity: Entity,
        recordID: String,
        operation: Operation,
        createdAt: Date = Date(),
        payload: Data? = nil,
        baseServerVersion: Int64? = nil,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        state: State = .pending,
        lastFailureCode: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.entity = entity
        self.recordID = recordID
        self.operation = operation
        self.createdAt = createdAt
        self.payload = payload
        self.baseServerVersion = baseServerVersion
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.nextAttemptAt = nextAttemptAt
        self.state = state
        self.lastFailureCode = lastFailureCode
    }


    private enum CodingKeys: String, CodingKey {
        case id, profileID, entity, recordID, operation, createdAt, payload
        case baseServerVersion, attemptCount, lastAttemptAt, nextAttemptAt, state, lastFailureCode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        profileID = try values.decode(LocalProfileID.self, forKey: .profileID)
        entity = try values.decode(Entity.self, forKey: .entity)
        recordID = try values.decode(String.self, forKey: .recordID)
        operation = try values.decode(Operation.self, forKey: .operation)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        payload = try values.decodeIfPresent(Data.self, forKey: .payload)
        baseServerVersion = try values.decodeIfPresent(Int64.self, forKey: .baseServerVersion)
        attemptCount = try values.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        nextAttemptAt = try values.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
        state = try values.decodeIfPresent(State.self, forKey: .state) ?? .pending
        lastFailureCode = try values.decodeIfPresent(String.self, forKey: .lastFailureCode)
    }
}

enum LocalMutationAttemptOutcome: Equatable, Sendable {
    case retryable(failureCode: String)
    case blocked(failureCode: String)
}

enum MutationRetryPolicy {
    static let maximumDelay: TimeInterval = 6 * 60 * 60

    static func nextAttemptDate(attemptCount: Int, attemptedAt: Date) -> Date {
        let exponent = max(0, min(attemptCount - 1, 10))
        let delay = min(30 * pow(2, Double(exponent)), maximumDelay)
        return attemptedAt.addingTimeInterval(delay)
    }
}
