import Foundation
import MCSystemLifecycle

struct UpdateAgentLocalization: @unchecked Sendable {
    static let preferencesDomain = "container.matrixreligio.com"
    static let languagePreferenceKey = "container.matrixreligio.com.app-language"

    let languageIdentifier: String
    private let localizedBundle: Bundle

    init(
        appBundle: Bundle = Self.containingApplicationBundle(),
        selectedLanguageRawValue: String? = Self.persistedLanguageSelection(),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        languageIdentifier = Self.resolveLanguage(
            selectedLanguageRawValue: selectedLanguageRawValue,
            preferredLanguages: preferredLanguages
        )
        localizedBundle = Self.localizedBundle(in: appBundle, languageIdentifier: languageIdentifier)
    }

    func title() -> String {
        localizedString("MacContainer runtime update")
    }

    func body(for state: RuntimeUpdateState) -> String {
        switch state {
        case let .available(version):
            let format = localizedString("Apple container %@ is compatibility-approved and ready to review.")
            return String(format: format, locale: Locale(identifier: languageIdentifier), version)
        case .pending:
            return localizedString("An approved runtime update is waiting. Open MacContainer for details.")
        case .held:
            return localizedString("A discovered runtime is held for safety. Open MacContainer for details.")
        case .rolledBack:
            return localizedString("The runtime update was rolled back. Open MacContainer for recovery details.")
        case .recoveryRequired:
            return localizedString("Runtime recovery requires attention in MacContainer.")
        default:
            return localizedString("Open MacContainer to review runtime update status.")
        }
    }

    func localizedString(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func resolveLanguage(
        selectedLanguageRawValue: String?,
        preferredLanguages: [String]
    ) -> String {
        let supported = Set(["en", "zh-Hans", "zh-Hant", "ja", "ko"])
        let hasExplicitSelection = selectedLanguageRawValue != "system" &&
            selectedLanguageRawValue.map(supported.contains) == true
        if let selectedLanguageRawValue, hasExplicitSelection {
            return selectedLanguageRawValue
        }

        for language in preferredLanguages {
            let normalized = language.lowercased().replacingOccurrences(of: "_", with: "-")
            if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
                return "zh-Hans"
            }
            let isTraditionalChinese = normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-tw") ||
                normalized.hasPrefix("zh-hk") || normalized.hasPrefix("zh-mo")
            if isTraditionalChinese {
                return "zh-Hant"
            }
            if normalized == "ja" || normalized.hasPrefix("ja-") {
                return "ja"
            }
            if normalized == "ko" || normalized.hasPrefix("ko-") {
                return "ko"
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return "en"
            }
        }
        return "en"
    }

    static func containingApplicationBundle(executableURL: URL? = Bundle.main.executableURL) -> Bundle {
        guard var candidate = executableURL?.standardizedFileURL else { return .main }
        candidate.deleteLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension == "app", let bundle = Bundle(url: candidate) {
                return bundle
            }
            candidate.deleteLastPathComponent()
        }
        return .main
    }

    private static func persistedLanguageSelection() -> String? {
        UserDefaults.standard.persistentDomain(forName: preferencesDomain)?[languagePreferenceKey] as? String
    }

    private static func localizedBundle(in appBundle: Bundle, languageIdentifier: String) -> Bundle {
        guard let path = appBundle.path(forResource: languageIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return appBundle
        }
        return bundle
    }
}
