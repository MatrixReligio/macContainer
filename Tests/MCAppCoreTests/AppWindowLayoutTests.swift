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
}
