#!/usr/bin/swift
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 4, arguments[0] == "--input", arguments[2] == "--output" else {
    FileHandle.standardError.write(Data("usage: summarize.swift --input <json> --output <json>\n".utf8))
    exit(64)
}

let input = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let output = URL(fileURLWithPath: arguments[3]).standardizedFileURL
let object = try JSONSerialization.jsonObject(with: Data(contentsOf: input))
guard JSONSerialization.isValidJSONObject(object) else {
    FileHandle.standardError.write(Data("invalid physical result JSON\n".utf8))
    exit(65)
}

let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output, options: .atomic)
