import MauryaEffects
import SwiftUI
import UniformTypeIdentifiers

struct EffectLibraryView: View {
    @Environment(\.locale) private var locale

    let router: AppRouter
    let service: any EffectProgramService

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: EffectProgramTransferDocument?
    @State private var showImportPreview = false
    @State private var fileError: String?
    @State private var showFileError = false
    @State private var nameAction: NameAction?
    @State private var nameZh = ""
    @State private var nameJa = ""
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if service.records.isEmpty, let message = service.errorMessage {
                AppStateView(state: .error(message: message))
            } else if service.records.isEmpty {
                ContentUnavailableView(
                    "effects.empty.title",
                    systemImage: "wand.and.stars",
                    description: Text("effects.empty.message")
                )
            } else {
                List {
                    if let message = service.errorMessage {
                        Section {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    ForEach(service.records, id: \.program.id) { record in
                        HStack {
                            Button {
                                service.select(id: record.program.id)
                                router.show(.editor)
                            } label: {
                                EffectProgramRow(record: record, selected: record.program.id == service.selectedID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("effects.open.hint")
                            Menu("effects.actions", systemImage: "ellipsis.circle") {
                                Button("feature.playback", systemImage: "play.fill") {
                                    service.select(id: record.program.id)
                                    router.show(.playback)
                                }
                                Button("effects.copy", systemImage: "doc.on.doc") {
                                    service.select(id: record.program.id)
                                    Task { await service.copySelected() }
                                }
                                if record.program.sourceKind == .blocks {
                                    Button("effects.copy.script", systemImage: "chevron.left.forwardslash.chevron.right") {
                                        service.select(id: record.program.id)
                                        Task { await service.copySelectedAsScript() }
                                    }
                                }
                                Button("effects.rename", systemImage: "pencil") {
                                    beginRename(record)
                                }
                                Button("effects.export", systemImage: "square.and.arrow.up") {
                                    service.select(id: record.program.id)
                                    prepareExport(all: false)
                                }
                                Button("share.open", systemImage: "qrcode") {
                                    service.select(id: record.program.id)
                                    router.showShareImport()
                                }
                                Button("effects.delete", systemImage: "trash", role: .destructive) {
                                    service.select(id: record.program.id)
                                    confirmDelete = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("feature.effects")
        .toolbar { toolbarContent }
        .task { await service.load() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Maurya-Effect"
        ) { result in
            if case let .failure(error) = result { record(error) }
            exportDocument = nil
        }
        .sheet(isPresented: $showImportPreview) {
            if let preview = service.importPreview {
                EffectImportPreviewView(preview: preview) { strategy in
                    showImportPreview = false
                    applyImport(strategy)
                }
            }
        }
        .alert("effects.file.error.title", isPresented: $showFileError) {
        } message: {
            Text(fileError ?? "")
        }
        .alert("effects.name.title", isPresented: nameDialogPresented) {
            TextField("effects.name.zh", text: $nameZh)
            TextField("effects.name.ja", text: $nameJa)
            Button("action.cancel", role: .cancel) { nameAction = nil }
            Button("action.save") { applyNameAction() }
                .disabled(
                    nameZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && nameJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("effects.name.message")
        }
        .alert("effects.delete.confirm.title", isPresented: $confirmDelete) {
            Button("action.cancel", role: .cancel) {}
            Button("effects.delete", role: .destructive) { Task { await service.deleteSelected() } }
        } message: {
            Text("effects.delete.confirm.message")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("effects.add", systemImage: "plus") {
                Button("effects.add.blocks", systemImage: "square.grid.3x3") {
                    beginCreate(.blocks)
                }
                Button("effects.add.script", systemImage: "chevron.left.forwardslash.chevron.right") {
                    beginCreate(.script)
                }
                Divider()
                Button("effects.import", systemImage: "square.and.arrow.down") { isImporting = true }
            }
            Menu("effects.actions", systemImage: "ellipsis.circle") {
                Button("effects.copy", systemImage: "doc.on.doc") {
                    Task { await service.copySelected() }
                }
                Button("effects.rename", systemImage: "pencil") {
                    if let record = service.selectedRecord() { beginRename(record) }
                }
                if service.selectedRecord()?.program.sourceKind == .blocks {
                    Button("effects.copy.script", systemImage: "chevron.left.forwardslash.chevron.right") {
                        Task { await service.copySelectedAsScript() }
                    }
                }
                Button("effects.export", systemImage: "square.and.arrow.up") { prepareExport(all: false) }
                Button("effects.export.all", systemImage: "square.and.arrow.up.on.square") { prepareExport(all: true) }
                Button("effects.delete", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            }
            .disabled(service.selectedID == nil)
            Button("share.open", systemImage: "square.and.arrow.up") {
                router.showShareImport()
            }
            .accessibilityIdentifier("effect-share-entry")
            Button("feature.playback", systemImage: "play.circle") { router.show(.playback) }
        }
    }

    private func prepareExport(all: Bool) {
        Task {
            do {
                exportDocument = try EffectProgramTransferDocument(
                    data: all ? await service.exportAll() : await service.exportSelected()
                )
                isExporting = true
            } catch { record(error) }
        }
    }

    private var nameDialogPresented: Binding<Bool> {
        Binding(get: { nameAction != nil }, set: { if $0 == false { nameAction = nil } })
    }

    private func beginCreate(_ kind: EffectSourceKind) {
        nameZh = ""
        nameJa = ""
        nameAction = .create(kind)
    }

    private func beginRename(_ record: EffectProgramRecord) {
        service.select(id: record.program.id)
        nameZh = record.program.nameZh
        nameJa = record.program.nameJa
        nameAction = .rename
    }

    private func applyNameAction() {
        let action = nameAction
        nameAction = nil
        Task {
            switch action {
            case let .create(kind): await service.create(kind: kind, nameZh: nameZh, nameJa: nameJa)
            case .rename: await service.renameSelected(nameZh: nameZh, nameJa: nameJa)
            case nil: break
            }
        }
    }

    private func importFile(_ result: Result<[URL], any Error>) {
        Task {
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                await service.previewImport(data)
                showImportPreview = service.importPreview != nil
            } catch { record(error) }
        }
    }

    private func applyImport(_ strategy: EffectImportConflictStrategy) {
        Task { await service.applyImport(strategy: strategy) }
    }

    private func record(_ error: any Error) {
        fileError = EffectErrorPresenter.message(
            for: error,
            language: EffectPresentationLanguage(locale: locale)
        )
        showFileError = true
    }
}

private struct EffectImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: EffectImportPreview
    let apply: (EffectImportConflictStrategy) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("effects.import.summary") {
                    LabeledContent("effects.import.valid", value: "\(preview.programs.count)")
                    LabeledContent("effects.import.conflicts", value: "\(preview.conflictIDs.count)")
                    LabeledContent("effects.import.errors", value: "\(preview.errors.count)")
                }
                if preview.programs.isEmpty == false {
                    Section("effects.import.programs") {
                        ForEach(preview.programs, id: \.id) { program in
                            VStack(alignment: .leading) {
                                Text(program.nameZh)
                                Text(program.nameJa).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if preview.errors.isEmpty == false {
                    Section("effects.import.error.details") {
                        ForEach(Array(preview.errors.enumerated()), id: \.offset) { _, error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }
                if preview.programs.isEmpty == false {
                    Section("effects.import.strategy") {
                        Button("effects.import.copy") { apply(.copy) }
                        Button("effects.import.overwrite") { apply(.overwrite) }
                        Button("effects.import.skip") { apply(.skip) }
                    }
                }
            }
            .navigationTitle("effects.import.conflict.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }
}

private enum NameAction {
    case create(EffectSourceKind)
    case rename
}

private struct EffectProgramRow: View {
    let record: EffectProgramRecord
    let selected: Bool

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(record.program.nameZh)
                    Text(record.program.nameJa)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: record.program.sourceKind == .blocks ? "square.grid.3x3" : "chevron.left.forwardslash.chevron.right")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.program.sourceKind == .blocks ? "effects.kind.blocks" : "effects.kind.script")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(effectSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Color.accent)
                    .accessibilityLabel("effects.selected")
            }
        }
        .contentShape(Rectangle())
        .frame(minHeight: DesignTokens.Size.minimumHitTarget)
    }

    private var effectSummary: String {
        let duration =
            record.program.estimatedDurationMilliseconds
            .map { String(format: "%.1fs", Double($0) / 1_000) }
            ?? (record.program.scriptSource.contains("forever") ? "∞" : "—")
        return "\(record.program.blockCount) · \(duration)"
    }
}
