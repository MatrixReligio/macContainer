#!/usr/bin/swift
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = [
    "run", "--quiet", "--package-path", repositoryRoot.path, "mc-attestation", "verify"
] + Array(CommandLine.arguments.dropFirst())
process.currentDirectoryURL = repositoryRoot
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
