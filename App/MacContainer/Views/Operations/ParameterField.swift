import AppKit
import MCContracts
import MCModel
import SwiftUI

struct ParameterField: View {
    let operation: OperationContract
    let parameter: ParameterContract
    @Binding var field: DraftField

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(LocalizedStringKey(parameter.labelKey))
                    .font(.headline)
                if parameter.required {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                ParameterHelpButton(operation: operation, parameter: parameter)
            }

            control

            HStack(spacing: 8) {
                Text(LocalizedStringKey(parameter.conciseHelpKey))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                Text(field.source.rawValue)
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(Color(nsColor: .labelColor))
            }

            if parameter.securityImpact == .destructive || parameter.securityImpact == .privileged {
                Label {
                    Text(parameter.securityImpact == .privileged
                        ? "May change privileged system state"
                        : "May permanently remove data")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(parameter.labelKey). \(parameter.required ? "Required" : "Optional")")
        .accessibilityIdentifier("parameter.\(operation.id).\(parameter.id)")
    }

    @ViewBuilder
    private var control: some View {
        if parameter.cardinality == .repeated {
            repeatedControl
        } else {
            singleControl
        }
    }

    @ViewBuilder
    private var repeatedControl: some View {
        switch parameter.valueType {
        case .keyValue:
            repeatedEditor(kind: .keyValue, prompt: "KEY=value, one per line")
        case .portMapping:
            repeatedEditor(kind: .portMapping, prompt: "host:container/protocol, one per line")
        case .mount:
            repeatedEditor(kind: .mount, prompt: "source:destination[:ro], one per line")
        default:
            repeatedEditor(kind: .strings, prompt: "One value per line")
        }
    }

    @ViewBuilder
    private var singleControl: some View {
        switch parameter.valueType {
        case .boolean:
            Toggle("Enabled", isOn: booleanBinding)
                .toggleStyle(.switch)
        case .integer:
            TextField("Integer", text: numericBinding(kind: .integer))
                .textFieldStyle(.roundedBorder)
        case .bytes:
            TextField("Bytes", text: numericBinding(kind: .bytes))
                .textFieldStyle(.roundedBorder)
        case .duration:
            HStack {
                TextField("Seconds", text: numericBinding(kind: .duration))
                    .textFieldStyle(.roundedBorder)
                Text("seconds")
                    .foregroundStyle(.primary)
            }
        case .enumeration, .signal:
            if parameter.acceptedValues.isEmpty {
                TextField("Value", text: stringBinding(path: false))
                    .textFieldStyle(.roundedBorder)
            } else {
                AccessibleValuePicker(
                    label: humanReadableParameterLabel,
                    values: parameter.acceptedValues,
                    selection: stringBinding(path: false)
                )
                .frame(maxWidth: .infinity, minHeight: 26)
            }
        case .keyValue:
            repeatedEditor(kind: .keyValue, prompt: "KEY=value")
        case .portMapping:
            repeatedEditor(kind: .portMapping, prompt: "host:container/protocol")
        case .mount:
            repeatedEditor(kind: .mount, prompt: "source:destination[:ro]")
        case .path:
            TextField("Path", text: stringBinding(path: true))
                .textFieldStyle(.roundedBorder)
        case .url:
            TextField("https://", text: stringBinding(path: false))
                .textFieldStyle(.roundedBorder)
        case .platform:
            TextField("linux/arm64", text: stringBinding(path: false))
                .textFieldStyle(.roundedBorder)
        case .string:
            if parameter.availability.requiredCapabilities.contains("secureCredentialInput") {
                SecureField("Value", text: secretBinding)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(
                    parameter.cardinality == .one ? "Required value" : "Optional value",
                    text: stringBinding(path: false)
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func repeatedEditor(kind: RepeatedKind, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: repeatedBinding(kind: kind))
                .font(.body.monospaced())
                .frame(minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text(prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
        }
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: {
                guard case let .bool(value) = field.value else { return false }
                return value
            },
            set: { setValue(.bool($0)) }
        )
    }

    private enum NumericKind {
        case integer
        case bytes
        case duration
    }

    private func numericBinding(kind: NumericKind) -> Binding<String> {
        Binding(
            get: {
                switch field.value {
                case let .integer(value): String(value)
                case let .bytes(value): String(value)
                case let .duration(value): String(value.seconds)
                default: ""
                }
            },
            set: { text in
                guard text.isEmpty == false, let value = Int64(text) else {
                    setValue(.none)
                    return
                }
                switch kind {
                case .integer: setValue(.integer(value))
                case .bytes: setValue(.bytes(value))
                case .duration: setValue(.duration(.seconds(value)))
                }
            }
        )
    }

    private func stringBinding(path: Bool) -> Binding<String> {
        Binding(
            get: {
                switch field.value {
                case let .string(value), let .path(value): value
                default: ""
                }
            },
            set: { setValue($0.isEmpty ? .none : (path ? .path($0) : .string($0))) }
        )
    }

    private var secretBinding: Binding<String> {
        Binding(
            get: {
                guard case let .secret(value) = field.value else { return "" }
                return value
            },
            set: { setValue($0.isEmpty ? .none : .secret($0)) }
        )
    }

    private enum RepeatedKind {
        case strings
        case keyValue
        case portMapping
        case mount
    }

    private func repeatedBinding(kind: RepeatedKind) -> Binding<String> {
        Binding(
            get: { repeatedDisplayValue(kind: kind) },
            set: { setValue(parseRepeated($0, kind: kind)) }
        )
    }

    private func repeatedDisplayValue(kind: RepeatedKind) -> String {
        switch (kind, field.value) {
        case let (.strings, .strings(values)):
            values.joined(separator: "\n")
        case let (.keyValue, .keyValues(values)):
            values.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        case let (.portMapping, .portMappings(values)):
            values.map(\.description).joined(separator: "\n")
        case let (.mount, .mounts(values)):
            values.map(\.description).joined(separator: "\n")
        default:
            ""
        }
    }

    private func parseRepeated(_ text: String, kind: RepeatedKind) -> FieldValue {
        let values = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        switch kind {
        case .strings:
            return values.isEmpty ? .none : .strings(values)
        case .keyValue:
            let pairs = values.compactMap(parseKeyValue)
            return pairs.isEmpty ? .none : .keyValues(pairs)
        case .portMapping:
            let mappings = values.compactMap(parsePortMapping)
            return mappings.isEmpty ? .none : .portMappings(mappings)
        case .mount:
            let mounts = values.compactMap(parseMount)
            return mounts.isEmpty ? .none : .mounts(mounts)
        }
    }

    private func parseKeyValue(_ text: String) -> KeyValue? {
        let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = parts.first, key.isEmpty == false else { return nil }
        return KeyValue(key: String(key), value: parts.count == 2 ? String(parts[1]) : "")
    }

    private func parsePortMapping(_ text: String) -> PortMapping? {
        let protocolParts = text.split(separator: "/", maxSplits: 1)
        let ports = protocolParts[0].split(separator: ":")
        guard ports.count >= 2,
              let hostPort = UInt16(ports[ports.count - 2]),
              let containerPort = UInt16(ports[ports.count - 1])
        else { return nil }
        let address = ports.count > 2 ? ports.dropLast(2).joined(separator: ":") : nil
        return PortMapping(
            hostAddress: address,
            hostPort: hostPort,
            containerPort: containerPort,
            protocolName: protocolParts.count == 2 ? String(protocolParts[1]) : "tcp"
        )
    }

    private func parseMount(_ text: String) -> Mount? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Mount(
            source: String(parts[0]),
            destination: String(parts[1]),
            readOnly: parts.dropFirst(2).contains("ro")
        )
    }

    private func setValue(_ value: FieldValue) {
        field = DraftField(value: value, source: .userOverride)
    }

    private var humanReadableParameterLabel: String {
        parameter.id.reduce(into: "") { result, character in
            if character.isUppercase, result.isEmpty == false {
                result.append(" ")
            }
            result.append(character)
        }
        .capitalized
    }
}

private struct AccessibleValuePicker: NSViewRepresentable {
    let label: String
    let values: [String]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.didSelect(_:))
        configure(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        configure(button)
    }

    private func configure(_ button: NSPopUpButton) {
        let expectedTitles = ["Not set"] + values
        if button.itemTitles != expectedTitles {
            button.removeAllItems()
            button.addItems(withTitles: expectedTitles)
        }
        button.selectItem(at: max(0, (values.firstIndex(of: selection) ?? -1) + 1))
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(selection.isEmpty ? "Not set" : selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AccessibleValuePicker

        init(parent: AccessibleValuePicker) {
            self.parent = parent
        }

        @objc func didSelect(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem - 1
            parent.selection = index >= 0 ? parent.values[index] : ""
        }
    }
}
