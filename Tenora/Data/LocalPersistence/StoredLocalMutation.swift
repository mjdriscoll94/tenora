import Foundation
import SwiftData

@Model
final class StoredLocalMutation {
    @Attribute(.unique) var id: UUID
    var profileIDValue: String
    var entityValue: String
    var recordID: String
    var operationValue: String
    var createdAt: Date
    var payload: Data?
    var baseServerVersion: Int64?
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextAttemptAt: Date?
    var stateValue: String
    var lastFailureCode: String?

    init(mutation: LocalMutation) {
        id = mutation.id
        profileIDValue = mutation.profileID.rawValue
        entityValue = mutation.entity.rawValue
        recordID = mutation.recordID
        operationValue = mutation.operation.rawValue
        createdAt = mutation.createdAt
        payload = mutation.payload
        baseServerVersion = mutation.baseServerVersion
        attemptCount = mutation.attemptCount
        lastAttemptAt = mutation.lastAttemptAt
        nextAttemptAt = mutation.nextAttemptAt
        stateValue = mutation.state.rawValue
        lastFailureCode = mutation.lastFailureCode
    }

    var domainModel: LocalMutation? {
        guard
            let entity = LocalMutation.Entity(rawValue: entityValue),
            let operation = LocalMutation.Operation(rawValue: operationValue),
            let state = LocalMutation.State(rawValue: stateValue)
        else { return nil }
        return LocalMutation(
            id: id,
            profileID: LocalProfileID(rawValue: profileIDValue),
            entity: entity,
            recordID: recordID,
            operation: operation,
            createdAt: createdAt,
            payload: payload,
            baseServerVersion: baseServerVersion,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptAt,
            nextAttemptAt: nextAttemptAt,
            state: state,
            lastFailureCode: lastFailureCode
        )
    }
}
