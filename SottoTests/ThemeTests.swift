import XCTest
@testable import Sotto

final class ThemeTests: XCTestCase {

    override func tearDown() {
        // Restore the app default so other tests / the app start clean.
        UserDefaults.standard.removeObject(forKey: "appTheme")
        ThemeManager.shared.select(.indigo)
        super.tearDown()
    }

    // MARK: - Pure theme resolution

    func testNamedResolvesKnownThemes() {
        XCTAssertEqual(Theme.named("Indigo"), .indigo)
        XCTAssertEqual(Theme.named("Rose"), .rose)
        XCTAssertEqual(Theme.named("Slate"), .slate)
    }

    func testNamedFallsBackToIndigoForUnknown() {
        XCTAssertEqual(Theme.named("NeonPink"), .indigo)
    }

    func testAllThemesHaveDistinctIds() {
        let ids = Theme.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - Selection & persistence (via the shared instance)

    func testSelectPersistsToUserDefaults() {
        ThemeManager.shared.select(.rose)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appTheme"), "Rose")
        XCTAssertEqual(ThemeManager.shared.current.id, "Rose")

        ThemeManager.shared.select(.slate)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "appTheme"), "Slate")
        XCTAssertEqual(ThemeManager.shared.current.id, "Slate")
    }
}
