import Foundation
import SwiftData

/// A sidecar keeps Phase 4 metadata additive and leaves the released content models intact.
@Model
final class StoredSyncMetadata {
    @Attribute(.unique) var key: String
    var entityValue: String
    var recordID: String
    var scopeValue: String
    var localOwnerProfileID: String
    var ownerUserID: UUID?
    var householdID: UUID?
    var serverVersion: Int64?
    var updatedAt: Date
    var deletedAt: Date?
    var stateValue: String
    var lastAcknowledgedAt: Date?

    init(
        entity: SyncEntity,
        recordID: String,
        localOwnerProfileID: LocalProfileID,
        updatedAt: Date
    ) {
        key = Self.key(entity: entity, recordID: recordID)
        entityValue = entity.rawValue
        self.recordID = recordID
        scopeValue = SyncRecordScope.personal.rawValue
        self.localOwnerProfileID = localOwnerProfileID.rawValue
        ownerUserID = nil
        householdID = nil
        serverVersion = nil
        self.updatedAt = updatedAt
        deletedAt = nil
        stateValue = SyncRecordState.localOnly.rawValue
        lastAcknowledgedAt = nil
    }

    static func key(entity: SyncEntity, recordID: String) -> String {
        "\(entity.rawValue)|\(recordID)"
    }

    var domainModel: PersonalSyncMetadata? {
        guard
            let entity = SyncEntity(rawValue: entityValue),
            let scope = SyncRecordScope(rawValue: scopeValue),
            let state = SyncRecordState(rawValue: stateValue)
        else { return nil }

        return PersonalSyncMetadata(
            entity: entity,
            recordID: recordID,
            scope: scope,
            localOwnerProfileID: LocalProfileID(rawValue: localOwnerProfileID),
            ownerUserID: ownerUserID,
            householdID: householdID,
            serverVersion: serverVersion,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            state: state,
            lastAcknowledgedAt: lastAcknowledgedAt
        )
    }
}
