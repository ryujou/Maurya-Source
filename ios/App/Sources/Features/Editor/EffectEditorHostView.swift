import MauryaEditor
import MauryaEffects
import SwiftUI

struct EffectEditorHostView: View {
    let service: any EffectProgramService
    let playbackService: any PlaybackControlService
    let runtime: AppRuntimeState
    let fixtureRecoveryVisible: Bool

    var body: some View {
        if let record = service.selectedRecord() {
            EffectEditorDocumentView(
                record: record,
                service: service,
                playbackService: playbackService,
                runtime: runtime,
                fixtureRecoveryVisible: fixtureRecoveryVisible
            )
            .id(record.program.id)
        } else {
            ContentUnavailableView(
                "editor.no.selection.title",
                systemImage: "doc.badge.exclamationmark",
                description: Text("editor.no.selection.message")
            )
            .navigationTitle("feature.editor")
        }
    }
}

private struct EffectEditorDocumentView: View {
    @Environment(\.locale) private var locale
    let record: EffectProgramRecord
    let service: any EffectProgramService
    let playbackService: any PlaybackControlService
    let runtime: AppRuntimeState
    let fixtureRecoveryVisible: Bool

    @StateObject private var model: MauryaEditorModel
    @State private var operationError: String?
    @State private var operationMessage: LocalizedStringKey?
    @State private var previewFrame: EffectFrame?

    init(
        record: EffectProgramRecord,
        service: any EffectProgramService,
        playbackService: any PlaybackControlService,
        runtime: AppRuntimeState,
        fixtureRecoveryVisible: Bool
    ) {
        self.record = record
        self.service = service
        self.playbackService = playbackService
        self.runtime = runtime
        self.fixtureRecoveryVisible = fixtureRecoveryVisible
        let url = URL.applicationSupportDirectory
            .appending(path: "Maurya/Editor", directoryHint: .isDirectory)
            .appending(path: "\(record.program.id).autosave.json")
        _model = StateObject(wrappedValue: MauryaEditorModel(autosaveURL: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            if fixtureRecoveryVisible {
                Label("ui.fixture.editor.recovery", systemImage: "arrow.counterclockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor-recovery-fixture")
            }
            EditorStatusView(phase: model.phase, version: model.bundleVersion)
            if playbackService.state != .idle {
                ViewThatFits {
                    HStack {
                        Text("editor.playback.state").bold()
                        PlaybackStatusText(state: playbackService.state)
                        Spacer()
                        playbackControls
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("editor.playback.state") {
                            PlaybackStatusText(state: playbackService.state)
                        }
                        playbackControls
                    }
                }
                .padding(.horizontal)
            }
            if let operationError {
                Label(operationError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let operationMessage {
                Label(operationMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Color.success)
                    .padding(.horizontal)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let previewFrame {
                SevenGroupEffectPreview(frame: previewFrame)
                    .padding()
            }
            MauryaEditorView(model: model, configuration: configuration)
        }
        .accessibilityIdentifier("effect-editor")
        .navigationTitle(record.program.nameZh)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            model.onEvent = handle
            model.onRejectedMessage = { error in
                operationError = EffectErrorPresenter.message(for: error, language: .init(locale: locale))
            }
        }
        .onDisappear {
            model.onEvent = nil
            model.onRejectedMessage = nil
        }
        .onChange(of: playbackService.state) { _, state in
            reflectPlaybackState(state)
        }
    }

    @ViewBuilder
    private var playbackControls: some View {
        HStack {
            if playbackService.state == .running {
                Button("playback.pause", systemImage: "pause.fill", action: playbackService.pause)
            } else if playbackService.state == .paused {
                Button("playback.resume", systemImage: "play.fill", action: playbackService.resume)
            }
            Button("playback.stop", systemImage: "stop.fill", role: .destructive, action: playbackService.stop)
        }
        .frame(minHeight: DesignTokens.Size.minimumHitTarget)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("editor.save", systemImage: "square.and.arrow.down") { saveLatest(runAfterSave: false) }
                .disabled(model.phase != .ready)
            Button("editor.run", systemImage: "play") { send(.run) }
                .disabled(model.phase != .ready || runtime.allowsRealtimeExecution == false)
            Menu("editor.tools", systemImage: "ellipsis.circle") {
                Button("editor.undo", systemImage: "arrow.uturn.backward") { send(.undo) }
                    .disabled(model.phase != .ready)
                Button("editor.redo", systemImage: "arrow.uturn.forward") { send(.redo) }
                    .disabled(model.phase != .ready)
                if record.program.sourceKind == .script {
                    Button("editor.format", systemImage: "text.alignleft") { formatScript() }
                        .disabled(model.phase != .ready)
                }
                Button("editor.preview", systemImage: "eye") { previewLatest() }
                    .disabled(model.phase != .ready)
            }
        }
    }

    private var configuration: MauryaEditorConfiguration {
        MauryaEditorConfiguration(
            editor: record.program.sourceKind == .blocks ? .blocks : .script,
            language: locale.language.languageCode == .japanese ? .japanese : .simplifiedChinese,
            initialDocument: initialDocument
        )
    }

    private var initialDocument: String {
        record.program.sourceKind == .blocks ? record.program.workspaceJSON : record.program.scriptSource
    }

    private func handle(_ event: EditorBridgeEvent) {
        switch event {
        case let .saveRequested(document):
            persist(document, runAfterSave: false)
        case let .runRequested(document):
            persist(document, runAfterSave: true)
        default:
            break
        }
    }

    private func saveLatest(runAfterSave: Bool) {
        persist(model.latestDocument ?? initialDocument, runAfterSave: runAfterSave)
    }

    private func send(_ command: EditorCommand) {
        do {
            try model.send(command)
            operationError = nil
        } catch {
            operationError = EffectErrorPresenter.message(for: error, language: .init(locale: locale))
        }
    }

    private func previewLatest() {
        do {
            previewFrame = try EffectProgramPreview.frame(
                record: record,
                document: model.latestDocument ?? initialDocument
            )
            operationError = nil
        } catch {
            previewFrame = nil
            operationError = EffectErrorPresenter.message(for: error, language: .init(locale: locale))
        }
    }

    private func formatScript() {
        do {
            let formatted = try EffectProgramPreview.formattedScript(
                record: record,
                document: model.latestDocument ?? initialDocument
            )
            try model.send(.load(formatted))
            operationError = nil
        } catch {
            operationError = EffectErrorPresenter.message(for: error, language: .init(locale: locale))
        }
    }

    private func persist(_ document: String, runAfterSave: Bool) {
        Task {
            do {
                _ = try await service.save(document: document)
                operationError = nil
                operationMessage = runAfterSave ? nil : "editor.save.succeeded"
                if runAfterSave {
                    switch playbackService.start() {
                    case .running:
                        operationMessage = "editor.run.started"
                    case .preparing:
                        break
                    case let .unavailable(reason), let .failed(reason):
                        operationError = localizedPlaybackReason(reason)
                    case .idle, .paused, .stopping:
                        operationError = String(localized: "playback.unavailable.connection-and-effect")
                    }
                }
            } catch {
                operationMessage = nil
                operationError = EffectErrorPresenter.message(for: error, language: .init(locale: locale))
            }
        }
    }

    private func reflectPlaybackState(_ state: PlaybackPresentationState) {
        switch state {
        case .running:
            operationError = nil
            operationMessage = "editor.run.started"
        case let .unavailable(reason), let .failed(reason):
            operationMessage = nil
            operationError = localizedPlaybackReason(reason)
        case .idle, .preparing, .paused, .stopping:
            break
        }
    }

    private func localizedPlaybackReason(_ reason: String) -> String {
        String(localized: String.LocalizationValue(reason))
    }
}
