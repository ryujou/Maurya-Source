import AVFoundation
import MauryaShare
import SwiftUI

struct ShareImportView: View {
    @Environment(\.locale) private var locale
    let initialToken: String?
    let importService: any ShareImportService
    @State private var token: String
    @State private var operationTask: Task<Void, Never>?
    @State private var scannerPresented = false
    @State private var cameraDenied = false
    private let scannerAvailabilityMode: ShareScannerAvailabilityMode

    init(initialToken: String?, importService: any ShareImportService) {
        self.initialToken = initialToken
        self.importService = importService
        _token = State(initialValue: initialToken ?? "")
        let arguments = ProcessInfo.processInfo.arguments
        scannerAvailabilityMode =
            arguments.contains("-maurya-ui-testing") && arguments.contains("-maurya-ui-scanner-unavailable")
            ? .forcedUnavailable
            : .live
    }

    var body: some View {
        Form {
            Section {
                Picker("share.section", selection: sectionBinding) {
                    Text("share.section.create").tag(ShareSection.create)
                    Text("share.section.import").tag(ShareSection.importShare)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("share.temporary.message")
            }

            if importService.section == .create {
                createContent
            } else {
                importContent
            }

            operationContent
        }
        .navigationTitle("share.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await importService.loadChoices()
            guard let initialToken, initialToken.isEmpty == false else { return }
            importService.show(.importShare)
            await importService.fetchForPreview(initialToken)
        }
        .onDisappear {
            operationTask?.cancel()
            importService.cancel()
        }
        .fullScreenCover(isPresented: $scannerPresented) {
            ShareQRScannerSheet(availabilityMode: scannerAvailabilityMode) { scannedToken in
                token = scannedToken
                start { await importService.fetchForPreview(scannedToken) }
            }
        }
        .alert("share.scan.permission.title", isPresented: $cameraDenied) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text("share.scan.permission.message")
        }
    }

    private var sectionBinding: Binding<ShareSection> {
        Binding(get: { importService.section }, set: { importService.show($0) })
    }

    @ViewBuilder
    private var createContent: some View {
        Section("share.effects") {
            if importService.effects.isEmpty {
                Text("share.create.empty.effects").foregroundStyle(.secondary)
            } else {
                ForEach(importService.effects) { effect in
                    ShareChoiceRow(name: displayName(effect.names), detailKey: effect.sourceKind) {
                        start { await importService.createEffect(id: effect.id) }
                    }
                }
            }
        }
        Section("share.palettes") {
            if importService.palettes.isEmpty {
                Text("share.create.empty.palettes").foregroundStyle(.secondary)
            } else {
                ForEach(importService.palettes) { palette in
                    ShareChoiceRow(name: displayName(palette.names), detail: palette.hex) {
                        start { await importService.createPalette(id: palette.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var importContent: some View {
        Section("share.import.section") {
            TextField("share.import.placeholder", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("share.import.preview", systemImage: "checkmark.shield") {
                start { await importService.fetchForPreview(token) }
            }
            .disabled(trimmedToken.isEmpty || isBusy)
            Button("share.scan.button", systemImage: "qrcode.viewfinder") {
                requestCameraAndScan()
            }
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var operationContent: some View {
        switch importService.operation {
        case .idle:
            Section("share.status") {
                Text(importService.section == .create ? "share.create.idle" : "share.validation.idle")
                    .foregroundStyle(.secondary)
            }
        case .busy:
            Section("share.status") {
                ProgressView("share.busy")
                Button("action.cancel", role: .cancel) {
                    operationTask?.cancel()
                    operationTask = nil
                    importService.cancel()
                }
            }
        case let .created(created, descriptor):
            Section("share.created") {
                LabeledContent("share.validation.token", value: created.token)
                LabeledContent("share.expires", value: created.expiresAt.formatted(date: .abbreviated, time: .shortened))
                ShareQRCodeView(descriptor: descriptor)
                ShareLink(item: created.shareURL) {
                    Label("share.system", systemImage: "square.and.arrow.up")
                        .frame(minHeight: DesignTokens.Size.minimumHitTarget)
                }
            }
        case let .preview(preview):
            Section("share.preview") {
                LabeledContent("share.preview.name", value: displayName(preview.pending.envelope.displayName))
                LabeledContent(
                    "share.preview.kind",
                    value: String(localized: preview.pending.envelope.kind == .effect ? "share.kind.effect" : "share.kind.palette")
                )
                SharePayloadPreview(envelope: preview.pending.envelope)
                if case let .palette(payload) = preview.pending.envelope.payload {
                    LabeledContent("share.preview.color", value: payload.hex)
                }
                Label("share.preview.verified", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(DesignTokens.Color.success)
                ForEach(preview.consumer.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                if preview.isAlreadyImported {
                    Label("share.import.duplicate", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Button("share.import.confirm", systemImage: "square.and.arrow.down") {
                    start { await importService.confirmImport() }
                }
                .disabled(preview.isAlreadyImported || isBusy)
            }
        case let .fixturePreview(preview):
            Section("share.preview") {
                Label("ui.fixture.label", systemImage: "testtube.2")
                    .foregroundStyle(.secondary)
                LabeledContent("share.preview.name", value: preview.name)
                LabeledContent("share.preview.kind", value: String(localized: String.LocalizationValue(preview.kindKey)))
                Text(preview.source).font(.caption.monospaced()).textSelection(.enabled)
                Label("share.preview.verified", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(DesignTokens.Color.success)
                Button("share.import.confirm", systemImage: "square.and.arrow.down") {
                    start { await importService.confirmImport() }
                }
            }
        case let .imported(completed):
            Section("share.status") {
                Label("share.import.complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Color.success)
                LabeledContent("share.import.local-id", value: completed.localID)
                Text("share.import.safe-message").foregroundStyle(.secondary)
            }
        case let .failed(message):
            Section("share.status") {
                AppStateView(state: .error(message: message))
                HStack {
                    Button("action.retry", systemImage: "arrow.clockwise") {
                        if importService.section == .importShare, trimmedToken.isEmpty == false {
                            start { await importService.fetchForPreview(token) }
                        } else {
                            start { await importService.loadChoices() }
                        }
                    }
                    Button("action.cancel", role: .cancel, action: importService.cancel)
                }
            }
        }
    }

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isBusy: Bool { importService.operation == .busy }

    private func start(_ operation: @escaping @MainActor () async -> Void) {
        operationTask?.cancel()
        operationTask = Task { await operation() }
    }

    private func requestCameraAndScan() {
        if scannerAvailabilityMode == .forcedUnavailable {
            scannerPresented = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            scannerPresented = true
        case .notDetermined:
            operationTask?.cancel()
            operationTask = Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    scannerPresented = true
                } else {
                    cameraDenied = true
                }
            }
        case .denied, .restricted:
            cameraDenied = true
        @unknown default:
            cameraDenied = true
        }
    }

    private func displayName(_ names: ShareDisplayName) -> String {
        locale.language.languageCode?.identifier == "ja"
            ? (names.ja.isEmpty ? names.zh : names.ja)
            : (names.zh.isEmpty ? names.ja : names.zh)
    }
}

private struct ShareChoiceRow: View {
    let name: String
    let detail: String
    let action: () -> Void

    init(name: String, detail: String, action: @escaping () -> Void) {
        self.name = name
        self.detail = detail
        self.action = action
    }

    init(name: String, detailKey: String, action: @escaping () -> Void) {
        self.init(name: name, detail: String(localized: String.LocalizationValue(detailKey)), action: action)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("share.generate", action: action)
                .buttonStyle(.bordered)
                .frame(minHeight: DesignTokens.Size.minimumHitTarget)
        }
    }
}

private struct ShareQRCodeView: View {
    let descriptor: ShareQRCodeDescriptor
    @State private var image: CGImage?
    @State private var renderFailed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityLabel("share.qr.accessibility")
            } else if renderFailed {
                ContentUnavailableView(
                    "share.qr.error.title",
                    systemImage: "qrcode",
                    description: Text("share.qr.error.message")
                )
            } else {
                ProgressView("share.qr.generating")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .background(.white)
        .task(id: descriptor.payload) {
            do {
                image = try ShareQRCodeGenerator.render(descriptor)
                renderFailed = false
            } catch {
                image = nil
                renderFailed = true
            }
        }
    }
}
