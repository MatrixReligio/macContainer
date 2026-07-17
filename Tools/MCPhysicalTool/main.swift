import Foundation
import MCSystemLifecycle

@main
enum MCPhysicalTool {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw UsageError()
        }
        arguments.removeFirst()

        switch command {
        case "preflight":
            try await preflight(arguments)
        case "compare-baseline":
            try compareBaseline(arguments)
        default:
            throw UsageError()
        }
    }

    private static func preflight(_ arguments: [String]) async throws {
        guard arguments.count == 2, arguments[0] == "--output" else {
            throw UsageError()
        }
        let outputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let result = try await PhysicalPreflight(environment: SystemPhysicalPreflightEnvironment()).run()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(result.baseline)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: outputURL, options: [.atomic])

        switch result.permission {
        case .safeToTest:
            print("SAFE_TO_TEST")
        case .refusedExistingState:
            print("REFUSED_EXISTING_STATE: \(result.refusalReasons.joined(separator: ","))")
            Foundation.exit(2)
        }
    }

    private static func compareBaseline(_ arguments: [String]) throws {
        guard arguments.count == 2 else { throw UsageError() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(
            MachineBaseline.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[0]))
        )
        let second = try decoder.decode(
            MachineBaseline.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        guard first.canonicalForComparison == second.canonicalForComparison else {
            print("BASELINE_MISMATCH")
            Foundation.exit(3)
        }
        print("BASELINE_MATCH")
    }
}

private struct UsageError: Error, CustomStringConvertible {
    var description: String {
        "usage: mc-physical preflight --output <path> | compare-baseline <before> <after>"
    }
}
