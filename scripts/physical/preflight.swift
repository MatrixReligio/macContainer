#!/usr/bin/swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--read-only" }
guard arguments.count == 2, arguments[0] == "--output" else {
    FileHandle.standardError.write(Data("usage: preflight.swift --output <path> --read-only\n".utf8))
    exit(64)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["run", "mc-physical", "preflight"] + arguments
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
