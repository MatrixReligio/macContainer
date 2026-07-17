#!/usr/bin/swift
import Foundation

private struct Document: Sendable {
    let url: URL
    let language: String
    let documentID: String
    let sourceRevision: String
    let anchors: [String]
    let body: String
}

private let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]
private let guides: [(filename: String, id: String)] = [
    ("USER_GUIDE.md", "user-guide"),
    ("INSTALLATION.md", "installation"),
    ("RUNTIME_UPDATES.md", "runtime-updates"),
    ("COMPLETE_UNINSTALLATION.md", "complete-uninstallation"),
    ("TROUBLESHOOTING.md", "troubleshooting")
]

private func fail(_ errors: [String]) -> Never {
    for error in errors.sorted() {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
    }
    exit(1)
}

private func captures(_ pattern: String, in value: String, group: Int = 1) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
        guard match.numberOfRanges > group, let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
    }
}

private func documentError(_ code: Int, _ description: String) -> NSError {
    NSError(domain: "DocParity", code: code, userInfo: [NSLocalizedDescriptionKey: description])
}

private func load(_ url: URL, expectedLanguage: String, expectedID: String) throws -> Document {
    let text = try String(contentsOf: url, encoding: .utf8)
    let frontMatterStart = text.index(text.startIndex, offsetBy: 4)
    guard text.hasPrefix("---\n"),
          let closing = text.range(of: "\n---\n", range: frontMatterStart ..< text.endIndex)
    else {
        throw documentError(1, "missing YAML front matter")
    }
    let frontMatter = String(text[text.index(text.startIndex, offsetBy: 4) ..< closing.lowerBound])
    var fields: [String: String] = [:]
    for line in frontMatter.split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
    guard fields["language"] == expectedLanguage else {
        throw documentError(2, "language must be \(expectedLanguage)")
    }
    guard fields["document_id"] == expectedID else {
        throw documentError(3, "document_id must be \(expectedID)")
    }
    guard let revision = fields["source_revision"],
          revision.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression) != nil
    else {
        throw documentError(4, "source_revision must be a Git revision")
    }
    let body = String(text[closing.upperBound...])
    let anchors = captures(#"<a id="([a-z0-9-]+)"></a>"#, in: body)
    guard anchors.isEmpty == false, Set(anchors).count == anchors.count else {
        throw documentError(5, "stable anchors are missing or duplicated")
    }
    return Document(
        url: url,
        language: expectedLanguage,
        documentID: expectedID,
        sourceRevision: revision,
        anchors: anchors,
        body: body
    )
}

private func validateLinks(in document: Document, errors: inout [String]) {
    let linkTargets = captures(#"\[[^\]]+\]\(([^)]+)\)"#, in: document.body)
    for target in linkTargets {
        if target.hasPrefix("https://") {
            if URL(string: target) == nil {
                errors.append("\(document.url.path): malformed external link \(target)")
            }
        } else if target.hasPrefix("mailto:") {
            if target.contains("@") == false {
                errors.append("\(document.url.path): malformed email link \(target)")
            }
        } else if target.hasPrefix("#") {
            if document.anchors.contains(String(target.dropFirst())) == false {
                errors.append("\(document.url.path): missing local anchor \(target)")
            }
        } else {
            let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
            let resolved = document.url.deletingLastPathComponent().appending(path: path).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolved.path) == false {
                errors.append("\(document.url.path): broken local link \(target)")
            }
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail(["usage: check-doc-parity.swift docs-directory README files..."]) }
let docsRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
let readmeByLanguage = Dictionary(uniqueKeysWithValues: arguments.dropFirst(2).compactMap { path -> (String, URL)? in
    let url = URL(fileURLWithPath: path)
    if url.lastPathComponent == "README.md" {
        return ("en", url)
    }
    let name = url.deletingPathExtension().lastPathComponent
    guard name.hasPrefix("README.") else { return nil }
    return (String(name.dropFirst("README.".count)), url)
})

var errors: [String] = []
private var documents: [String: [String: Document]] = [:]
for language in languages {
    var specs = guides.map { (docsRoot.appending(path: language).appending(path: $0.filename), $0.id) }
    if let readme = readmeByLanguage[language] {
        specs.append((readme, "readme"))
    } else {
        errors.append("missing README for \(language)")
    }
    for (url, id) in specs {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("missing document: \(url.path)")
            continue
        }
        do {
            let document = try load(url, expectedLanguage: language, expectedID: id)
            documents[id, default: [:]][language] = document
            validateLinks(in: document, errors: &errors)
            if id != "readme" {
                let containsCommandBlock = document.body.contains("```console") ||
                    document.body.contains("```bash") || document.body.contains("```sh") ||
                    document.body.contains("```zsh")
                if containsCommandBlock {
                    errors.append("\(url.path): user workflow must be command-free")
                }
            }
        } catch {
            errors.append("\(url.path): \(error.localizedDescription)")
        }
    }
}

for (id, localized) in documents {
    guard let english = localized["en"] else { continue }
    for language in languages {
        guard let document = localized[language] else { continue }
        if document.sourceRevision != english.sourceRevision {
            errors.append("\(id) \(language): stale source_revision")
        }
        if document.anchors != english.anchors {
            errors.append("\(id) \(language): stable heading IDs differ from English")
        }
    }
}

if errors.isEmpty == false {
    fail(errors)
}

let count = documents.values.reduce(0) { $0 + $1.count }
guard count == 30 else { fail(["expected 30 localized documents, found \(count)"]) }
print("Document parity PASS: 30 localized documents, 0 stale revisions, 0 broken links")
