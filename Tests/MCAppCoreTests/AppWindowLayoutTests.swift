@testable import MCAppCore
import Testing

@Suite("Application window layout")
struct AppWindowLayoutTests {
    @Test func `default window fits a 1024 by 768 desktop and honors content minimums`() {
        #expect(AppWindowLayout.defaultContentWidth == 960)
        #expect(AppWindowLayout.defaultContentHeight == 680)
        #expect(AppWindowLayout.minimumContentWidth == 940)
        #expect(AppWindowLayout.minimumContentHeight == 620)
        #expect(AppWindowLayout.defaultContentWidth <= 1024)
        #expect(AppWindowLayout.defaultContentHeight + AppWindowLayout.titlebarAllowance <= 768)
    }

    @Test func `settings content keeps readable margins and responsive inventory columns`() {
        #expect(AppWindowLayout.settingsContentMaxWidth == 960)
        #expect(AppWindowLayout.settingsHorizontalInset == 24)
        #expect(AppWindowLayout.settingsSidebarWidth == 220)
        #expect(AppWindowLayout.settingsSectionSpacing == 20)
        #expect(AppWindowLayout.inventoryColumnMinimumWidth == 240)
        #expect(
            AppWindowLayout.settingsContentMaxWidth + 2 * AppWindowLayout.settingsHorizontalInset <=
                AppWindowLayout.defaultContentWidth + 2 * AppWindowLayout.settingsHorizontalInset
        )
    }
}
