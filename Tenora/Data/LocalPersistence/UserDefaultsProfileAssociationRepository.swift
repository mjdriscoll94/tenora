import Foundation

@MainActor
final class UserDefaultsProfileAssociationRepository: ProfileAssociationRepository {
    private static let storageKey = "profiles.account-associations.v1"
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func association(for accountUserID: UUID) -> LocalProfileAssociation? {
        associations.first { $0.accountUserID == accountUserID }
    }

    func association(for profileID: LocalProfileID) -> LocalProfileAssociation? {
        associations.first { $0.profileID == profileID && $0.status == .complete }
    }

    func begin(accountUserID: UUID, profileID: LocalProfileID) throws {
        var values = associations
        if let owner = values.first(where: {
            $0.profileID == profileID && $0.status == .complete && $0.accountUserID != accountUserID
        }), owner.accountUserID != accountUserID {
            throw ProfileAssociationError.profileAlreadyAssociated
        }

        values.removeAll { $0.accountUserID == accountUserID }
        values.append(LocalProfileAssociation(
            accountUserID: accountUserID,
            profileID: profileID,
            status: .pending,
            updatedAt: now()
        ))
        save(values)
    }

    func complete(accountUserID: UUID) throws -> LocalProfileAssociation {
        var values = associations
        guard let index = values.firstIndex(where: {
            $0.accountUserID == accountUserID && $0.status == .pending
        }) else {
            throw ProfileAssociationError.missingPendingAssociation
        }
        let completed = LocalProfileAssociation(
            accountUserID: accountUserID,
            profileID: values[index].profileID,
            status: .complete,
            updatedAt: now()
        )
        values[index] = completed
        save(values)
        return completed
    }

    func removePending(accountUserID: UUID) {
        save(associations.filter { !($0.accountUserID == accountUserID && $0.status == .pending) })
    }

    private var associations: [LocalProfileAssociation] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([LocalProfileAssociation].self, from: data)) ?? []
    }

    private func save(_ values: [LocalProfileAssociation]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
