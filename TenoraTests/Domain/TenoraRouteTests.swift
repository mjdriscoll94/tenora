import XCTest
@testable import Tenora

final class TenoraRouteTests: XCTestCase {
    func testCaptureDecodesTextWithoutSavingIt() {
        XCTAssertEqual(TenoraRoute(url: URL(string: "tenora://add?title=Call%20John")!), .capture("Call John"))
    }
    func testTaskIdentityAndInvalidRoutes() {
        let id = UUID()
        XCTAssertEqual(TenoraRoute(url: URL(string: "tenora://task/\(id)")!), .task(id))
        XCTAssertNil(TenoraRoute(url: URL(string: "tenora://task/not-an-id")!))
        XCTAssertNil(TenoraRoute(url: URL(string: "https://add")!))
    }
}
