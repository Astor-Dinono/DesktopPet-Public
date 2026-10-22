import XCTest
@testable import DesktopPet

final class UpdaterTests: XCTestCase {
    private var valid: [String: Any] { [
        "SUFeedURL": "https://updates.example.com/appcast.xml",
        "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
        "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false,
        "SUEnableSystemProfiling": false, "SUVerifyUpdateBeforeExtraction": true,
        "SURequireSignedFeed": true,
    ] }

    func testValidSignedManualUpdateConfiguration() {
        let configuration = DogUpdateConfiguration(info: valid)
        XCTAssertEqual(configuration?.feedURL.absoluteString, "https://updates.example.com/appcast.xml")
        XCTAssertEqual(configuration?.publicKey.count, 32)
    }

    func testRejectsUnsafeOrIdentifyingFeedURLs() {
        for url in ["http://updates.example.com/feed", "file:///tmp/feed", "https://user:password@example.com/feed",
                    "https://example.com/feed?count=12", "https://example.com/feed#fragment", "invalid"] {
            var info = valid; info["SUFeedURL"] = url
            XCTAssertNil(DogUpdateConfiguration(info: info), url)
        }
    }

    func testRejectsMissingOrWrongLengthUpdateKey() {
        for key in ["invalid", Data(repeating: 0, count: 31).base64EncodedString(), ""] {
            var info = valid; info["SUPublicEDKey"] = key
            XCTAssertNil(DogUpdateConfiguration(info: info))
        }
    }

    func testRequiresManualPrivateAndVerifiedUpdatePolicy() {
        for key in ["SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUEnableSystemProfiling",
                    "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
            var info = valid; info[key] = !(info[key] as! Bool)
            XCTAssertNil(DogUpdateConfiguration(info: info), key)
            info = valid; info.removeValue(forKey: key)
            XCTAssertNil(DogUpdateConfiguration(info: info), key)
        }
    }
}
