#!/usr/bin/swift
import Foundation

private let locales = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]
private let fields = ["labelKey", "conciseHelpKey", "detailedHelpKey", "validationErrorKey", "recoveryKey"]
private let detailMarkers: [String: [String]] = [
    "en": [
        "Purpose:", "Upstream default:", "Accepted values or format:", "Repeat and order behavior:",
        "Dependencies and conflicts:", "OS, hardware, and runtime limits:",
        "Security or data impact:", "Example:", "Recovery:"
    ],
    "zh-Hans": ["用途：", "上游默认值：", "可接受值或格式：", "重复与顺序：", "依赖与冲突：", "系统限制：", "安全或数据影响：", "示例：", "恢复："],
    "zh-Hant": ["用途：", "上游預設值：", "可接受值或格式：", "重複與順序：", "相依性與衝突：", "系統限制：", "安全性或資料影響：", "範例：", "復原："],
    "ja": ["目的:", "上流の既定値:", "使用可能な値または形式:", "反復と順序:", "依存関係と競合:", "システム制限:", "セキュリティまたはデータへの影響:", "例:", "復旧:"],
    "ko": ["목적:", "업스트림 기본값:", "허용 값 또는 형식:", "반복 및 순서:", "종속성과 충돌:", "시스템 제한:", "보안 또는 데이터 영향:", "예:", "복구:"]
]

private func fail(_ messages: [String]) -> Never {
    for message in messages.sorted() {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail(["usage: check-parameter-help.swift contract.json Localizable.xcstrings"]) }
guard let contract = try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
) as? [String: Any],
    let operations = contract["operations"] as? [[String: Any]]
else { fail(["invalid contract JSON"]) }
guard let catalog = try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
) as? [String: Any],
    let strings = catalog["strings"] as? [String: Any]
else { fail(["invalid string catalog JSON"]) }

var errors: [String] = []
var parameterCount = 0
var requiredKeys = Set<String>()
for operation in operations {
    guard let operationID = operation["id"] as? String,
          let parameters = operation["parameters"] as? [[String: Any]] else { continue }
    for parameter in parameters {
        parameterCount += 1
        let parameterID = parameter["id"] as? String ?? "unknown"
        for field in fields {
            guard let key = parameter[field] as? String else {
                errors.append("\(operationID).\(parameterID) missing \(field)")
                continue
            }
            requiredKeys.insert(key)
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any]
            else {
                errors.append("missing parameter key \(key)")
                continue
            }
            for locale in locales {
                guard let localization = localizations[locale] as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String,
                      value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                else {
                    errors.append("\(key) missing nonempty \(locale)")
                    continue
                }
                if field == "detailedHelpKey" {
                    let minimumLength = ["en": 350, "zh-Hans": 180, "zh-Hant": 180, "ja": 230, "ko": 230][locale] ?? 240
                    if value.count < minimumLength {
                        errors.append("\(key) \(locale) detail is too short")
                    }
                    for marker in detailMarkers[locale] ?? [] where value.contains(marker) == false {
                        errors.append("\(key) \(locale) detail missing section \(marker)")
                    }
                }
            }
        }
    }
}

if errors.isEmpty == false {
    fail(errors)
}

print("Parameter help PASS: \(parameterCount) parameter instances, \(requiredKeys.count) help keys, five languages")
