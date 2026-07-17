import Foundation
import MCModel

public struct ErrorMapper: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public func map(
        _ error: any Error,
        domain: UserFacingErrorDomain,
        operationID: String,
        activityID: UUID? = nil
    ) -> UserFacingError {
        let raw = String(describing: error)
        let code = errorCode(raw: raw, domain: domain)
        return UserFacingError(
            code: code,
            domain: domain,
            operationID: operationID,
            titleKey: "\(code).title",
            explanationKey: "\(code).explanation",
            diagnosticDetail: Self.redact(raw),
            retryIsSafe: retryIsSafe(domain: domain, operationID: operationID),
            recoveryActions: recoveryActions(domain: domain),
            activityID: activityID,
            timestamp: now()
        )
    }

    private func errorCode(raw: String, domain: UserFacingErrorDomain) -> String {
        let lowercase = raw.lowercased()
        let isAuthenticationFailure = lowercase.contains("authorization") ||
            lowercase.contains("credential") || lowercase.contains("password") ||
            lowercase.contains("bearer")
        if isAuthenticationFailure {
            return "error.authentication"
        }
        let isMalformedUpstreamData = lowercase.contains("malformed") ||
            lowercase.contains("expected") || lowercase.contains("decode")
        if isMalformedUpstreamData {
            return "error.upstream-data"
        }
        return "error.\(domain.rawValue)"
    }

    private func retryIsSafe(domain: UserFacingErrorDomain, operationID: String) -> Bool {
        guard domain != .helper, domain != .lifecycle, domain != .compatibility else {
            return false
        }
        let destructiveMarkers = ["delete", "remove", "prune", "uninstall", "rollback", "logout"]
        return !destructiveMarkers.contains { operationID.lowercased().contains($0) }
    }

    private func recoveryActions(domain: UserFacingErrorDomain) -> [ErrorRecoveryAction] {
        switch domain {
        case .registry:
            [
                .init(id: "edit-credentials", titleKey: "error.action.edit-credentials"),
                .init(id: "retry", titleKey: "error.action.retry")
            ]
        case .helper:
            [
                .init(id: "review-authorization", titleKey: "error.action.review-authorization"),
                .init(id: "open-activity", titleKey: "error.action.open-activity")
            ]
        case .compatibility:
            [
                .init(id: "view-compatibility-report", titleKey: "error.action.compatibility-report"),
                .init(id: "open-activity", titleKey: "error.action.open-activity")
            ]
        case .lifecycle:
            [
                .init(id: "resume-recovery", titleKey: "error.action.resume-recovery"),
                .init(id: "open-activity", titleKey: "error.action.open-activity")
            ]
        default:
            [
                .init(id: "retry", titleKey: "error.action.retry"),
                .init(id: "open-activity", titleKey: "error.action.open-activity")
            ]
        }
    }

    private static func redact(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let rules: [(String, String)] = [
            (#"(?i)authorization\s*:\s*(?:bearer|basic)\s+[^;\s,]+"#, "Authorization: <redacted>"),
            (
                #"(?i)\b(password|passwd|secret|credential|api[_-]?key|api[_-]?token|token)\b\s*[:=]\s*[^;\s,]+"#,
                "$1=<redacted>"
            ),
            (#"(?i)\b(user|username)\b\s*[:=]\s*[^;\s,]+"#, "$1=<redacted>"),
            (#"(?i)([a-z][a-z0-9+.-]*://)[^/@\s]+@"#, "$1<redacted>@"),
            (#"/(?:private/)?var/folders/[^;\s,]+"#, "<temporary>"),
            (#"/Users/[^/\s]+"#, "<home>")
        ]
        for (pattern, replacement) in rules {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            value = expression.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: replacement
            )
        }
        return String(value.prefix(2048))
    }
}
