#!/usr/bin/swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: compare-baseline.swift <before> <after>\n".utf8))
    exit(64)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["run", "mc-physical", "compare-baseline"] + arguments
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
