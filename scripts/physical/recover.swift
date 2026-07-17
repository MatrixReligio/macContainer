#!/usr/bin/swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let forwarded: [String]
if arguments == ["--assert-no-active-ledger"] {
    forwarded = ["assert-no-active-ledger", ".artifacts/physical"]
} else if arguments.count == 4, arguments[0] == "--run-root", arguments[2] == "--run-id" {
    forwarded = ["recover"] + arguments
} else {
    FileHandle.standardError.write(
        Data("usage: recover.swift --run-root <path> --run-id <uuid> | --assert-no-active-ledger\n".utf8)
    )
    exit(64)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["run", "mc-physical"] + forwarded
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
