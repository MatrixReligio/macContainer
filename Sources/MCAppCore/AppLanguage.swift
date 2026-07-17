import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    public var displayName: String {
        switch self {
        case .system: "System Language"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

public enum LanguageChangeResult: Equatable, Sendable {
    case noChange
    case saveBeforeRelaunch
    case waitForActivities
    case readyToRelaunch
}

public enum LanguageChangeError: Error, Equatable, Sendable {
    case activeOperations
    case noPendingChange
    case unsavedWork
}
