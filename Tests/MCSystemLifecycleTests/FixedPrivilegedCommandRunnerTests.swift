import Foundation
@testable import MCSystemLifecycle
import Testing

@Suite("Fixed privileged command runner")
struct FixedPrivilegedCommandRunnerTests {
    @Test func `returns stdout without merging stderr diagnostics`() throws {
        let invocation = FixedPrivilegedCommandInvocation(
            command: .inspectContainerPacketFilter,
            packageDescriptor: nil,
            executable: "/bin/sh",
            arguments: ["/bin/sh", "-c", "printf 'rule-output'; printf 'diagnostic' >&2"],
            environment: [:],
            workingDirectory: "/"
        )

        let output = try PosixSpawnFixedPrivilegedCommandRunner().run(
            invocation,
            standardInput: nil,
            package: nil
        )

        #expect(try #require(String(data: output, encoding: .utf8)) == "rule-output")
    }
}
