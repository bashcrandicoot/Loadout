import XCTest
@testable import Loadout

/// Sparkle's settings in Info.plist: Loadout's own feed and key (never Lodge's).
final class UpdatesTests: XCTestCase {
    private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

    func testFeedIsLoadoutsAppcastOnMain() {
        XCTAssertEqual(info("SUFeedURL") as? String,
                       "https://raw.githubusercontent.com/bashcrandicoot/Loadout/main/appcast.xml")
    }

    func testPublicKeyIsLoadoutsOwn() {
        let key = info("SUPublicEDKey") as? String
        XCTAssertEqual(key, "KCsaD0Nx8QWbHtSsAw2uxKYLaxTRRlqCPUz22laTU+g=")
        XCTAssertNotEqual(key, "9Y5ssl+tCdpqaggzyIUbmUkGlcm77uCP8TvU4QcjmR4=", "That's Lodge's key.")
        XCTAssertEqual(Data(base64Encoded: key ?? "")?.count, 32, "An Ed25519 public key is 32 bytes.")
    }

    func testDailyAutomaticChecks() {
        XCTAssertEqual(info("SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(info("SUScheduledCheckInterval") as? Int, 86400)
    }

    @MainActor func testUpdaterNeverStartsInTheTestHost() {
        XCTAssertFalse(AppUpdates.updater.sessionInProgress)
        XCTAssertFalse(AppUpdates.updater.canCheckForUpdates, "Not started, so it can't check.")
    }
}
