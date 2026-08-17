import MauryaResources
import SwiftUI
import UniformTypeIdentifiers

struct ResourceLibraryView: View {
    @Environment(\.locale) private var locale
    let service: any ResourceLibraryService
    @State private var searchText = ""
    @State private var editorItem: CustomPalettePresentation?
    @State private var editorPresented = false
    @State private var exporterPresented = false
    @State private var importerPresented = false
    @State private var exportDocument: PaletteBackupDocument?
    @State private var pendingImport: Data?
    @State private var importPolicyPresented = false
    @State private var undoAvailable = false
    @State private var fileError: String?
    @State private var pendingDelete: CustomPalettePresentation?

    var body: some View {
        Group {
            if service.snapshot == nil, let message = service.errorMessage {
                AppStateView(state: .error(message: message))
            } else if let snapshot = service.snapshot {
                List {
                    if let message = service.errorMessage {
                        Section("state.error.title") {
                            Text(message).foregroundStyle(.red)
                            Button("action.retry", systemImage: "arrow.clockwise") {
                                Task { await service.load() }
                            }
                        }
                    }
                    customSection(snapshot)
                    Section("resources.builtin") {
                        if filtered(snapshot.entries).isEmpty {
                            ContentUnavailableView.search
                        } else {
                            ForEach(filtered(snapshot.entries)) { entry in ResourceRow(entry: entry) }
                        }
                    }
                }
            } else {
                ProgressView("state.loading")
            }
        }
        .navigationTitle("feature.resources")
        .searchable(text: $searchText)
        .toolbar { toolbarContent }
        .task { await service.load() }
        .sheet(isPresented: $editorPresented) {
            CustomPaletteEditorView(
                existing: editorItem?.entry,
                existingAvatar: editorItem?.avatarWebP
            ) { zh, ja, hex, imageData, cropTransform in
                await service.saveCustom(
                    existingID: editorItem?.entry.id,
                    expectedRevision: editorItem?.entry.revision ?? 0,
                    nameZh: zh,
                    nameJa: ja,
                    hex: hex,
                    sourceImageData: imageData,
                    cropTransform: cropTransform
                )
            }
        }
        .fileExporter(
            isPresented: $exporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Maurya-palettes"
        ) { result in
            if case let .failure(error) = result { fileError = describe(error) }
            exportDocument = nil
        }
        .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try Data(contentsOf: url, options: .mappedIfSafe)
                importPolicyPresented = true
            } catch {
                pendingImport = nil
                fileError = describe(error)
            }
        }
        .confirmationDialog("resources.custom.import.policy", isPresented: $importPolicyPresented) {
            Button("resources.custom.import.overwrite") { applyImport(.overwrite) }
            Button("resources.custom.import.skip") { applyImport(.skip) }
            Button("action.cancel", role: .cancel) { pendingImport = nil }
        }
        .confirmationDialog("resources.custom.delete.title", isPresented: deleteConfirmationPresented) {
            Button("action.delete", role: .destructive, action: deletePending)
            Button("action.cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("resources.custom.delete.message")
        }
        .alert("resources.custom.file.error.title", isPresented: fileErrorPresented) {
        } message: {
            Text(fileError ?? "")
        }
    }

    @ViewBuilder
    private func customSection(_ snapshot: ResourceLibrarySnapshot) -> some View {
        Section {
            LabeledContent("resources.custom.count", value: "\(snapshot.customCount) / \(snapshot.customLimit)")
            ForEach(snapshot.customEntries) { item in
                let entry = item.entry
                Button {
                    editorItem = item
                    editorPresented = true
                } label: {
                    HStack {
                        if let image = UIImage(data: item.avatarWebP) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 44, height: 44).clipShape(Circle())
                        } else {
                            Circle().fill(color(entry.color.rawValue)).frame(width: 44, height: 44)
                        }
                        VStack(alignment: .leading) {
                            Text(displayName(entry.names))
                            Text(entry.color.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("action.edit")
                .swipeActions {
                    Button("action.delete", role: .destructive) {
                        pendingDelete = item
                    }
                    Button("action.edit") {
                        editorItem = item
                        editorPresented = true
                    }.tint(.blue)
                }
            }
            if undoAvailable {
                Button("action.undo", systemImage: "arrow.uturn.backward") {
                    Task {
                        if await service.undoDelete() { undoAvailable = false }
                    }
                }
            }
        } header: {
            HStack {
                Text("resources.custom")
                Spacer()
                Button("resources.custom.add", systemImage: "plus") {
                    editorItem = nil
                    editorPresented = true
                }
                .disabled(snapshot.customCount >= snapshot.customLimit)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("resources.custom.import", systemImage: "square.and.arrow.down") { importerPresented = true }
            Button("resources.custom.export", systemImage: "square.and.arrow.up") {
                Task {
                    do {
                        let data = try await service.exportBackup()
                        exportDocument = PaletteBackupDocument(data: data)
                        exporterPresented = true
                    } catch { fileError = describe(error) }
                }
            }
        }
    }

    private func applyImport(_ policy: BackupConflictPolicy) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task { _ = await service.importBackup(data, conflictPolicy: policy) }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if $0 == false { pendingDelete = nil } }
        )
    }

    private func deletePending() {
        guard let item = pendingDelete else { return }
        pendingDelete = nil
        Task {
            undoAvailable = await service.deleteCustom(
                id: item.entry.id,
                expectedRevision: item.entry.revision
            )
        }
    }

    private func filtered(_ entries: [ResourceInventoryEntry]) -> [ResourceInventoryEntry] {
        guard searchText.isEmpty == false else { return entries }
        return entries.filter {
            $0.nameZh.localizedStandardContains(searchText) || $0.nameJa.localizedStandardContains(searchText)
                || $0.affiliation.localizedStandardContains(searchText)
        }
    }

    private func displayName(_ names: PaletteNames) -> String {
        locale.language.languageCode?.identifier == "ja"
            ? (names.ja.isEmpty ? names.zh : names.ja)
            : (names.zh.isEmpty ? names.ja : names.zh)
    }

    private func color(_ hex: String) -> Color {
        guard let value = UInt64(hex.dropFirst(), radix: 16), hex.count == 7 else { return .clear }
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    private var fileErrorPresented: Binding<Bool> {
        Binding(
            get: { fileError != nil },
            set: { if $0 == false { fileError = nil } }
        )
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
