import XCTest
@testable import WhoopAPI

final class WhoopAPITests: XCTestCase {
    func testAuthorizationURLContainsScopes() {
        let url = WhoopOAuth.authorizationURL(clientID: "test", redirectURI: "myapp://callback")
        XCTAssertTrue(url.absoluteString.contains("read%3Arecovery"))
        XCTAssertTrue(url.absoluteString.contains("client_id=test"))
    }

    func testDefaultScopesIncludeOffline() {
        XCTAssertTrue(WhoopOAuth.defaultScopes.contains("offline"))
        XCTAssertTrue(WhoopOAuth.defaultScopes.contains("read:sleep"))
    }
}
