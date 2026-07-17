import Foundation

/// Validates the explicit, per-run capability used by destructive physical tests.
/// Empty Xcode build-setting expansions must never authorize a physical test.
public enum PhysicalTestAuthorization {
    public static func validatedRunID(environment: [String: String]) -> String? {
        guard let runID = environment["PHYSICAL_RUN_ID"],
              let uuid = UUID(uuidString: runID),
              uuid.uuidString.lowercased() == runID,
              environment["PHYSICAL_TEST_AUTHORIZATION"] == runID,
              let root = environment["PHYSICAL_RUN_ROOT"]
        else {
            return nil
        }

        let standardizedRoot = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
        guard standardizedRoot.lastPathComponent == runID else { return nil }
        return runID
    }
}
