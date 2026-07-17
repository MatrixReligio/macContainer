@testable import MCAppCore
import Testing

@Suite("App language")
@MainActor
struct LanguageControllerTests {
    @Test(arguments: [
        ResolutionFixture(.system, ["zh-Hans-CN"], "zh-Hans"),
        .init(.system, ["zh-Hant-TW"], "zh-Hant"),
        .init(.system, ["ja-JP"], "ja"),
        .init(.system, ["ko-KR"], "ko"),
        .init(.system, ["fr-FR"], "en"),
        .init(.english, ["zh-Hans"], "en"),
        .init(.simplifiedChinese, ["en"], "zh-Hans"),
        .init(.traditionalChinese, ["en"], "zh-Hant"),
        .init(.japanese, ["en"], "ja"),
        .init(.korean, ["en"], "ko")
    ])
    func `resolves exact supported language or English fallback`(
        _ input: ResolutionFixture
    ) {
        #expect(LanguageController.resolve(
            selection: input.selection,
            preferredLanguages: input.preferredLanguages
        ) == input.expected)
    }

    @Test func `request never discards unsaved or active work`() {
        let storage = RecordingLanguageStorage()
        let controller = LanguageController(storage: storage)

        #expect(controller.request(.japanese, hasUnsavedWork: true, hasActiveOperations: false) ==
            .saveBeforeRelaunch)
        #expect(controller.selection == .system)
        #expect(controller.pendingSelection == .japanese)
        #expect(storage.saved.isEmpty)

        #expect(controller.request(.korean, hasUnsavedWork: false, hasActiveOperations: true) ==
            .waitForActivities)
        #expect(storage.saved.isEmpty)
    }

    @Test func `confirmed change persists only the enum and requires relaunch`() throws {
        let storage = RecordingLanguageStorage()
        let controller = LanguageController(storage: storage)
        #expect(controller.request(.english, hasUnsavedWork: false, hasActiveOperations: false) ==
            .readyToRelaunch)
        #expect(controller.requiresRelaunch)

        try controller.confirmForRelaunch(hasUnsavedWork: false, hasActiveOperations: false)
        #expect(storage.saved == [AppLanguage.english.rawValue])
        #expect(controller.selection == .english)
        #expect(controller.pendingSelection == nil)
    }

    @Test func `corrupt persistence fails closed to system and cancellation clears pending`() {
        let storage = RecordingLanguageStorage(loaded: "remote-or-invalid")
        let controller = LanguageController(storage: storage)
        #expect(controller.selection == .system)
        _ = controller.request(.japanese, hasUnsavedWork: false, hasActiveOperations: false)
        controller.cancelPendingChange()
        #expect(controller.pendingSelection == nil)
        #expect(controller.requiresRelaunch == false)
    }
}

struct ResolutionFixture: Sendable {
    let selection: AppLanguage
    let preferredLanguages: [String]
    let expected: String

    init(_ selection: AppLanguage, _ preferredLanguages: [String], _ expected: String) {
        self.selection = selection
        self.preferredLanguages = preferredLanguages
        self.expected = expected
    }
}

@MainActor
private final class RecordingLanguageStorage: LanguageSelectionStoring {
    let loaded: String?
    var saved: [String] = []

    init(loaded: String? = nil) {
        self.loaded = loaded
    }

    func load() -> String? {
        loaded
    }

    func save(_ rawValue: String) throws {
        saved.append(rawValue)
    }
}
