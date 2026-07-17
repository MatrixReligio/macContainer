import Foundation
import Observation

@MainActor
public protocol LanguageSelectionStoring: AnyObject {
    func load() -> String?
    func save(_ rawValue: String) throws
}

@MainActor
public final class UserDefaultsLanguageSelectionStore: LanguageSelectionStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "container.matrixreligio.com.app-language"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> String? {
        defaults.string(forKey: key)
    }

    public func save(_ rawValue: String) throws {
        defaults.set(rawValue, forKey: key)
    }
}

@MainActor
@Observable
public final class LanguageController {
    public private(set) var selection: AppLanguage
    public private(set) var pendingSelection: AppLanguage?
    public private(set) var pendingResult: LanguageChangeResult = .noChange

    @ObservationIgnored private let storage: any LanguageSelectionStoring

    public var requiresRelaunch: Bool {
        pendingSelection != nil && pendingSelection != selection
    }

    public var resolvedIdentifier: String {
        Self.resolve(selection: selection, preferredLanguages: Locale.preferredLanguages)
    }

    public init(storage: any LanguageSelectionStoring = UserDefaultsLanguageSelectionStore()) {
        self.storage = storage
        selection = storage.load().flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    @discardableResult
    public func request(
        _ language: AppLanguage,
        hasUnsavedWork: Bool,
        hasActiveOperations: Bool
    ) -> LanguageChangeResult {
        guard language != selection else {
            pendingSelection = nil
            pendingResult = .noChange
            return .noChange
        }
        pendingSelection = language
        if hasUnsavedWork {
            pendingResult = .saveBeforeRelaunch
        } else if hasActiveOperations {
            pendingResult = .waitForActivities
        } else {
            pendingResult = .readyToRelaunch
        }
        return pendingResult
    }

    public func confirmForRelaunch(
        hasUnsavedWork: Bool,
        hasActiveOperations: Bool
    ) throws {
        guard let pendingSelection else { throw LanguageChangeError.noPendingChange }
        guard hasUnsavedWork == false else { throw LanguageChangeError.unsavedWork }
        guard hasActiveOperations == false else { throw LanguageChangeError.activeOperations }
        try storage.save(pendingSelection.rawValue)
        selection = pendingSelection
        self.pendingSelection = nil
        pendingResult = .noChange
    }

    public func cancelPendingChange() {
        pendingSelection = nil
        pendingResult = .noChange
    }

    public static func resolve(
        selection: AppLanguage,
        preferredLanguages: [String]
    ) -> String {
        guard selection == .system else { return selection.rawValue }
        for language in preferredLanguages {
            let normalized = language.lowercased().replacingOccurrences(of: "_", with: "-")
            let isSimplifiedChinese = normalized.hasPrefix("zh-hans") ||
                normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg")
            if isSimplifiedChinese {
                return AppLanguage.simplifiedChinese.rawValue
            }
            let isTraditionalChinese = normalized.hasPrefix("zh-hant") ||
                normalized.hasPrefix("zh-tw") || normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo")
            if isTraditionalChinese {
                return AppLanguage.traditionalChinese.rawValue
            }
            if normalized == "ja" || normalized.hasPrefix("ja-") {
                return AppLanguage.japanese.rawValue
            }
            if normalized == "ko" || normalized.hasPrefix("ko-") {
                return AppLanguage.korean.rawValue
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return AppLanguage.english.rawValue
            }
        }
        return AppLanguage.english.rawValue
    }
}
