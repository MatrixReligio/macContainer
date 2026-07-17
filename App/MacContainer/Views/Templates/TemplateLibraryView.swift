import MCModel
import MCTemplates
import SwiftUI
import UniformTypeIdentifiers

struct TemplateLibraryView: View {
    @Binding var isPresented: Bool

    @State private var customTemplates: [TemplateDocument] = []
    @State private var importPresented = false
    @State private var exportPresented = false
    @State private var importedPreview: TemplateDocument?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button("Import") { importPresented = true }
                        .accessibilityIdentifier("import-template")
                    Button("Export") { exportPresented = true }
                        .accessibilityIdentifier("export-template")
                    Button("Duplicate") { duplicateExample() }
                        .accessibilityIdentifier("duplicate-template")
                    Spacer()
                }
                .padding()

                Divider()

                List {
                    Section("Built in") {
                        ForEach(BuiltInTemplates.all) { template in
                            Label(template.id, systemImage: "checkmark.seal.fill")
                        }
                    }
                    Section("Custom") {
                        if customTemplates.isEmpty {
                            Text("No custom templates")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(customTemplates) { document in
                                VStack(alignment: .leading) {
                                    Text(document.name)
                                    Text(document.operationID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let importedPreview {
                        Section("Import preview") {
                            LabeledContent("Name", value: importedPreview.name)
                            LabeledContent("Operation", value: importedPreview.operationID)
                            Text("No secrets detected. Save only after reviewing every value.")
                                .font(.caption)
                        }
                    }
                    if let errorMessage {
                        Section("Import blocked") {
                            Label(errorMessage, systemImage: "xmark.shield.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Template Library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 540)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("template-library")
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json]) { result in
            importTemplate(result)
        }
        .fileExporter(
            isPresented: $exportPresented,
            document: TemplateExportDocument(document: exportExample),
            contentType: .json,
            defaultFilename: "maccontainer-template"
        ) { _ in }
    }

    private var exportExample: TemplateDocument {
        TemplateDocument(
            id: "quick-run-copy",
            name: "Quick run copy",
            operationID: "core.run",
            fields: ["image": DraftField(value: .string("alpine:latest"), source: .userOverride)]
        )
    }

    private func duplicateExample() {
        let suffix = customTemplates.count + 1
        customTemplates.append(TemplateDocument(
            id: "quick-run-copy-\(suffix)",
            name: "Quick run copy \(suffix)",
            operationID: exportExample.operationID,
            fields: exportExample.fields
        ))
    }

    private func importTemplate(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            importedPreview = try TemplateDocumentCodec().import(Data(contentsOf: url, options: [.mappedIfSafe]))
            errorMessage = nil
        } catch {
            importedPreview = nil
            errorMessage = "The template is corrupt, unsupported, or contains sensitive data."
        }
    }
}

private struct TemplateExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    private let data: Data

    init(document: TemplateDocument) {
        data = (try? TemplateDocumentCodec().export(document)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
