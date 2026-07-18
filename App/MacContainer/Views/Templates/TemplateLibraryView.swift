import MCAppCore
import MCModel
import MCTemplates
import SwiftUI
import UniformTypeIdentifiers

struct TemplateLibraryView: View {
    @Binding var isPresented: Bool

    @State private var customTemplates: [TemplateDocument] = []
    @State private var selectedBuiltInID: String? = BuiltInTemplates.all.first?.id
    @State private var selectedCustomID: String?
    @State private var editingDocument: TemplateDocument?
    @State private var importPresented = false
    @State private var exportPresented = false
    @State private var exportDocument: TemplateDocument?
    @State private var errorMessage: String?

    private static let store = TemplateStore(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("container.matrixreligio.com", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true),
        fileSystem: LocalTemplateFileSystem()
    )

    var body: some View {
        NavigationStack {
            HSplitView {
                templateList
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                templateDetail
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Template Library")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New…") { createCustomTemplate() }
                        .accessibilityIdentifier("new-custom-template")
                    Button("Import") { importPresented = true }
                        .accessibilityIdentifier("import-template")
                    Button("Export") { prepareExport() }
                        .disabled(selectedDocument == nil)
                        .accessibilityIdentifier("export-template")
                    Button("Duplicate") { duplicateSelection() }
                        .disabled(selectedBuiltIn == nil && selectedDocument == nil)
                        .accessibilityIdentifier("duplicate-template")
                    Button("Delete") { deleteSelection() }
                        .disabled(selectedDocument == nil)
                        .accessibilityIdentifier("delete-template")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .accessibilityIdentifier("template-library-done")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("template-library")
        .task { await reloadTemplates() }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json]) { result in
            importTemplate(result)
        }
        .fileExporter(
            isPresented: $exportPresented,
            document: TemplateExportDocument(document: exportDocument ?? Self.fallbackDocument),
            contentType: .json,
            defaultFilename: exportDocument?.id ?? "maccontainer-template"
        ) { _ in }
    }

    private var templateList: some View {
        List {
            Section("Built in") {
                ForEach(BuiltInTemplates.all) { template in
                    Button {
                        selectBuiltIn(template.id)
                    } label: {
                        Label(template.id, systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedBuiltInID == template.id ? Color.accentColor.opacity(0.16) : nil)
                    .accessibilityIdentifier("library-template.\(template.id)")
                }
            }
            Section("Custom") {
                if customTemplates.isEmpty {
                    Text("No custom templates")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customTemplates) { document in
                        Button {
                            selectCustom(document)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.name)
                                Text(document.operationID)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedCustomID == document.id ? Color.accentColor.opacity(0.16) : nil)
                        .accessibilityIdentifier("custom-template.\(document.id)")
                    }
                }
            }
        }
        .contentMargins(.top, AppWindowLayout.templateLibraryTopInset, for: .scrollContent)
        .accessibilityLabel("Templates")
    }

    private var templateDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let template = selectedBuiltIn {
                    let metadata = TemplateMetadata(template)
                    Label(metadata.title, systemImage: metadata.symbol)
                        .font(.title2.bold())
                    Text(metadata.summary)
                        .font(.body)
                    LabeledContent("ID", value: template.id)
                    LabeledContent("Operation", value: template.operationID)
                    // swiftlint:disable:next line_length
                    Text("Eight built-in scenarios are immutable. Imported templates are migrated and checked for secrets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Duplicate") { duplicateSelection() }
                } else if editingDocument != nil {
                    customEditor
                } else {
                    ContentUnavailableView("No custom templates", systemImage: "doc.badge.plus")
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.shield.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("template-library-error")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .topLeading)
        }
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom")
                .font(.title2.bold())
            LabeledContent("ID", value: editingDocument?.id ?? "")
            TextField("Name", text: documentName)
            Picker("Operation", selection: documentOperationID) {
                Text(verbatim: "core.run").tag("core.run")
                Text(verbatim: "machines.create").tag("machines.create")
            }
            if editingDocument?.fields["image"] != nil {
                TextField("Image reference", text: stringField("image"))
            }
            if editingDocument?.fields["name"] != nil {
                TextField("Name", text: stringField("name"))
            }
            Button("Save") { saveEditingDocument() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("save-custom-template")
        }
    }

    private var selectedBuiltIn: ScenarioTemplate? {
        selectedBuiltInID.flatMap { id in BuiltInTemplates.all.first { $0.id == id } }
    }

    private var selectedDocument: TemplateDocument? {
        guard let selectedCustomID else { return nil }
        return customTemplates.first { $0.id == selectedCustomID }
    }

    private var documentName: Binding<String> {
        Binding(
            get: { editingDocument?.name ?? "" },
            set: { editingDocument?.name = $0 }
        )
    }

    private var documentOperationID: Binding<String> {
        Binding(
            get: { editingDocument?.operationID ?? "core.run" },
            set: { editingDocument?.operationID = $0 }
        )
    }

    private func stringField(_ id: String) -> Binding<String> {
        Binding(
            get: {
                guard case let .string(value) = editingDocument?.fields[id]?.value else { return "" }
                return value
            },
            set: { value in
                editingDocument?.fields[id] = DraftField(value: .string(value), source: .userOverride)
            }
        )
    }

    private func selectBuiltIn(_ id: String) {
        selectedBuiltInID = id
        selectedCustomID = nil
        editingDocument = nil
        errorMessage = nil
    }

    private func selectCustom(_ document: TemplateDocument) {
        selectedBuiltInID = nil
        selectedCustomID = document.id
        editingDocument = document
        errorMessage = nil
    }

    private func createCustomTemplate() {
        let document = Self.newDocument(operationID: "core.run")
        persistAndSelect(document)
    }

    private func duplicateSelection() {
        if let selectedDocument {
            var duplicate = selectedDocument
            duplicate = TemplateDocument(
                id: Self.newID(),
                name: "\(duplicate.name) copy",
                operationID: duplicate.operationID,
                fields: duplicate.fields
            )
            persistAndSelect(duplicate)
        } else if let selectedBuiltIn {
            persistAndSelect(Self.newDocument(operationID: selectedBuiltIn.operationID))
        }
    }

    private func saveEditingDocument() {
        guard let editingDocument else { return }
        persistAndSelect(editingDocument)
    }

    private func persistAndSelect(_ document: TemplateDocument) {
        Task {
            do {
                try await Self.store.save(document)
                await reloadTemplates(selecting: document.id)
                errorMessage = nil
            } catch {
                errorMessage = "The template is corrupt, unsupported, or contains sensitive data."
            }
        }
    }

    private func deleteSelection() {
        guard let selectedCustomID else { return }
        Task {
            do {
                try await Self.store.remove(id: selectedCustomID)
                await reloadTemplates()
                selectBuiltIn(BuiltInTemplates.all.first?.id ?? "quick-run")
            } catch {
                errorMessage = "The template is corrupt, unsupported, or contains sensitive data."
            }
        }
    }

    private func prepareExport() {
        guard let selectedDocument else { return }
        exportDocument = selectedDocument
        exportPresented = true
    }

    private func importTemplate(_ result: Result<URL, any Error>) {
        Task {
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let document = try TemplateDocumentCodec().import(Data(contentsOf: url, options: [.mappedIfSafe]))
                try await Self.store.save(document)
                await reloadTemplates(selecting: document.id)
                errorMessage = nil
            } catch {
                errorMessage = "The template is corrupt, unsupported, or contains sensitive data."
            }
        }
    }

    @MainActor
    private func reloadTemplates(selecting id: String? = nil) async {
        do {
            customTemplates = try await Self.store.listEnabled()
            if let id, let document = customTemplates.first(where: { $0.id == id }) {
                selectCustom(document)
            } else if let selectedCustomID {
                let document = customTemplates.first(where: { $0.id == selectedCustomID })
                editingDocument = document
            } else if selectedBuiltInID == nil {
                selectBuiltIn(BuiltInTemplates.all.first?.id ?? "quick-run")
            }
        } catch {
            errorMessage = "The template is corrupt, unsupported, or contains sensitive data."
        }
    }

    private static func newDocument(operationID: String) -> TemplateDocument {
        TemplateDocument(
            id: newID(),
            name: operationID == "machines.create" ? "Linux machine" : "Run once",
            operationID: operationID,
            fields: [
                "image": DraftField(value: .string("alpine:latest"), source: .userOverride),
                "name": DraftField(value: .string("custom-workload"), source: .userOverride)
            ]
        )
    }

    private static func newID() -> String {
        "custom-\(UUID().uuidString.lowercased().prefix(12))"
    }

    private static let fallbackDocument = TemplateDocument(
        id: "custom-template",
        name: "Run once",
        operationID: "core.run",
        fields: [:]
    )
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
