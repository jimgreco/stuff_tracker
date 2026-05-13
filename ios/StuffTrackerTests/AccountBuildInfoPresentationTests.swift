import XCTest
@testable import StuffTracker

final class AccountBuildInfoPresentationTests: XCTestCase {
    func testBuildInfoTextIncludesVersionBuildAndGitHash() {
        let text = AccountBuildInfoPresentation.text(info: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
            "GitCommitHash": "abc1234",
        ])

        XCTAssertEqual(text, "Version 1.2.3 (42) - abc1234")
    }

    func testBuildInfoTextFallsBackWhenBundleValuesAreMissing() {
        XCTAssertEqual(
            AccountBuildInfoPresentation.text(info: [:]),
            "Version Unknown (Unknown) - Unknown"
        )
        XCTAssertEqual(
            AccountBuildInfoPresentation.text(info: nil),
            "Version Unknown (Unknown) - Unknown"
        )
    }
}
