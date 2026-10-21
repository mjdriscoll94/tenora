import Foundation

@MainActor
protocol ProfileRepository: AnyObject {
    var activeProfileID: LocalProfileID { get }
    func activate(_ profileID: LocalProfileID)
    func returnToOfflineProfile()
}
