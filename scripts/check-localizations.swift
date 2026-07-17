#!/usr/bin/swift
import Foundation

private let requiredLocales = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]
private let rejectedStates = ["needs_review", "stale", "new"]

private func fail(_ messages: [String]) -> Never {
    for message in messages.sorted() {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
    exit(1)
}

private func placeholders(in value: String) -> [String] {
    let pattern = #"%(?:(\d+)\$)?[-+#0 ']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDuUxXoOfFeEgGaAcCsSp])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var implicitIndex = 0
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
        implicitIndex += 1
        let position: String
        if match.range(at: 1).location == NSNotFound {
            position = String(implicitIndex)
        } else if let range = Range(match.range(at: 1), in: value) {
            position = String(value[range])
        } else {
            return nil
        }
        guard let typeRange = Range(match.range(at: 2), in: value) else { return nil }
        return "\(position):\(value[typeRange].lowercased())"
    }.sorted()
}

private func catalog(at url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
        throw CocoaError(.propertyListReadCorrupt)
    }
    return value
}

private func staticUIKeys(in sourceRoot: URL) -> Set<String> {
    // swiftlint:disable:next line_length
    let pattern = #"(?:Text|Label|Button|Toggle|TextField|SecureField|Picker|LabeledContent|Section|GroupBox|Menu|ContentUnavailableView|navigationTitle|help|accessibilityLabel|alert|confirmationDialog)\s*\(\s*"((?:\\.|[^"\\])*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
    var keys = Set<String>()
    while let url = enumerator?.nextObject() as? URL {
        guard url.pathExtension == "swift", let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let key = String(source[range])
            guard key.contains(#"\("#) == false else { continue }
            keys.insert(key.replacingOccurrences(of: #"\""#, with: #"""#))
        }
    }
    return keys
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fail(["usage: check-localizations.swift resources-directory"]) }
let resources = URL(fileURLWithPath: arguments[1], isDirectory: true)
let names = ["Localizable.xcstrings", "InfoPlist.xcstrings"]
var errors: [String] = []
var keyCount = 0
var localizableKeys = Set<String>()

for name in names {
    let url = resources.appending(path: name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        errors.append("missing catalog: \(name)")
        continue
    }
    do {
        let root = try catalog(at: url)
        if root["sourceLanguage"] as? String != "en" {
            errors.append("\(name): sourceLanguage must be en")
        }
        guard let strings = root["strings"] as? [String: Any] else {
            errors.append("\(name): missing strings object")
            continue
        }
        if name == "Localizable.xcstrings" {
            localizableKeys = Set(strings.keys)
        }
        keyCount += strings.count
        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any]
            else {
                errors.append("\(name): \(key) has no localizations")
                continue
            }
            var values: [String: String] = [:]
            for locale in requiredLocales {
                guard let localization = localizations[locale] as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let state = unit["state"] as? String,
                      let value = unit["value"] as? String
                else {
                    errors.append("\(name): \(key) missing \(locale)")
                    continue
                }
                if rejectedStates.contains(state.lowercased()) || state.lowercased() != "translated" {
                    errors.append("\(name): \(key) \(locale) has rejected state \(state)")
                }
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("\(name): \(key) \(locale) is empty")
                }
                values[locale] = value
            }
            if let english = values["en"] {
                let expected = placeholders(in: english)
                for locale in requiredLocales where locale != "en" {
                    if let value = values[locale], placeholders(in: value) != expected {
                        errors.append("\(name): \(key) \(locale) placeholder types differ from en")
                    }
                }
            }
        }
    } catch {
        errors.append("\(name): invalid JSON: \(error)")
    }
}

let sourceRoot = resources.deletingLastPathComponent()
for key in staticUIKeys(in: sourceRoot).sorted() where localizableKeys.contains(key) == false {
    errors.append("Localizable.xcstrings: static UI key missing: \(key)")
}

if errors.isEmpty == false {
    fail(errors)
}

print("Localization catalogs PASS: \(keyCount) keys, five complete languages")
