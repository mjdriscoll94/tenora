import Foundation

protocol TenoraClock: Sendable {
    var now: Date { get }
}

struct SystemClock: TenoraClock {
    var now: Date { Date() }
}

