import Foundation
import MCModel

enum TemplateSecretPolicy {
    static func firstSensitiveField(in document: TemplateDocument) -> String? {
        document.fields.keys.sorted().first { id in
            guard let value = document.fields[id]?.value else {
                return false
            }
            return value.containsSecret || sensitiveIdentifier(id) || sensitiveValue(value)
        }
    }

    private static func sensitiveIdentifier(_ identifier: String) -> Bool {
        let normalized = identifier.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { String($0).lowercased() }
            .joined()
        return sensitiveIdentifierFragments.contains { normalized.contains($0) } ||
            normalized == "auth" || normalized == "registryauth"
    }

    private static func sensitiveValue(_ value: FieldValue) -> Bool {
        switch value {
        case .secret:
            true
        case let .string(value), let .path(value):
            sensitiveText(value)
        case let .strings(values):
            values.contains(where: sensitiveText)
        case let .keyValues(values):
            values.contains { sensitiveIdentifier($0.key) || sensitiveText($0.value) }
        case let .mounts(values):
            values.contains { sensitiveText($0.source) || sensitiveText($0.destination) }
        case .bool, .integer, .bytes, .duration, .portMappings, .none:
            false
        }
    }

    private static func sensitiveText(_ text: String) -> Bool {
        let lowercase = text.lowercased()
        if privateKeyMarkers.contains(where: lowercase.contains) {
            return true
        }
        if authorizationMarkers.contains(where: lowercase.contains) {
            return true
        }
        return assignmentKeys.contains { key in
            lowercase.contains("\(key)=") ||
                lowercase.contains("\(key):") ||
                lowercase.contains("\"\(key)\":")
        }
    }

    private static let sensitiveIdentifierFragments = [
        "password",
        "passwd",
        "token",
        "secret",
        "credential",
        "privatekey",
        "authorization"
    ]

    private static let assignmentKeys = [
        "password",
        "passwd",
        "token",
        "secret",
        "credential",
        "authorization",
        "auth"
    ]

    private static let privateKeyMarkers = [
        "-----begin private key-----",
        "-----begin rsa private key-----",
        "-----begin ec private key-----",
        "-----begin openssh private key-----"
    ]

    private static let authorizationMarkers = [
        "authorization:",
        "authorization=",
        "bearer ",
        "basic "
    ]
}
