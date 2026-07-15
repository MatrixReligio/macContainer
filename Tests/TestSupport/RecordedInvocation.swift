import Foundation

public enum RecordedInvocationError: Error, Equatable, Sendable {
    case sensitiveArgument(String)
}

public struct RecordedInvocation: Codable, Equatable, Sendable {
    public let operationID: String
    public let resourceIDs: [String]
    public let redactedArguments: [String: String]

    public init(
        operationID: String,
        resourceIDs: [String],
        redactedArguments: [String: String]
    ) throws {
        if let sensitiveKey = redactedArguments.keys.sorted().first(where: { key in
            Self.isSensitive(key: key, value: redactedArguments[key] ?? "")
        }) {
            throw RecordedInvocationError.sensitiveArgument(sensitiveKey)
        }
        self.operationID = operationID
        self.resourceIDs = resourceIDs
        self.redactedArguments = redactedArguments
    }

    private static func isSensitive(key: String, value: String) -> Bool {
        let normalizedKey = key.lowercased().filter(\.isLetter)
        let lowercaseValue = value.lowercased()
        let sensitiveKey = ["password", "token", "secret", "authorization", "credential"].contains {
            normalizedKey.contains($0)
        }
        if sensitiveKey, value != "<redacted>" {
            return true
        }
        return ["authorization:", "bearer ", "basic ", "-----begin private key-----"].contains {
            lowercaseValue.contains($0)
        }
    }
}

public actor InvocationRecorder {
    private var invocations: [RecordedInvocation] = []

    public init() {}

    public func record(_ invocation: RecordedInvocation) {
        invocations.append(invocation)
    }

    public func snapshot() -> [RecordedInvocation] {
        invocations
    }
}
