import MauryaShare
import Observation
import SwiftUI
import UIKit
import VisionKit

enum ShareScannerAvailabilityMode: Equatable {
    case live
    case forcedUnavailable

    @MainActor
    var canAttemptScanning: Bool {
        switch self {
        case .live:
            DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        case .forcedUnavailable:
            false
        }
    }
}

enum ShareScannerPresentationState: Equatable {
    case loading
    case running
    case unavailable
}

@MainActor
@Observable
final class ShareScannerPresentationModel {
    private(set) var state: ShareScannerPresentationState
    private(set) var retryGeneration = 0

    init(canAttemptScanning: Bool) {
        state = canAttemptScanning ? .loading : .unavailable
    }

    func scannerWillStart() {
        state = .loading
    }

    func scannerDidStart() {
        state = .running
    }

    func scannerBecameUnavailable() {
        state = .unavailable
    }

    func retry(canAttemptScanning: Bool) {
        retryGeneration &+= 1
        state = canAttemptScanning ? .loading : .unavailable
    }
}

struct ShareQRScannerSheet: View {
    let onToken: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ShareScannerPresentationModel
    private let availabilityMode: ShareScannerAvailabilityMode

    @MainActor
    init(
        availabilityMode: ShareScannerAvailabilityMode = .live,
        onToken: @escaping (String) -> Void
    ) {
        self.availabilityMode = availabilityMode
        self.onToken = onToken
        _model = State(
            initialValue: ShareScannerPresentationModel(
                canAttemptScanning: availabilityMode.canAttemptScanning
            ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if availabilityMode.canAttemptScanning {
                    ShareDataScanner(
                        isApplicationActive: scenePhase == .active,
                        retryGeneration: model.retryGeneration,
                        onWillStart: model.scannerWillStart,
                        onStarted: model.scannerDidStart,
                        onUnavailable: model.scannerBecameUnavailable,
                        onToken: deliver
                    )
                    .ignoresSafeArea(edges: .bottom)
                }

                switch model.state {
                case .loading:
                    ProgressView("state.loading")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("share-scanner-loading")
                case .running:
                    Text("share.scan.hint")
                        .font(.callout)
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .accessibilityIdentifier("share-scanner-running")
                case .unavailable:
                    unavailableContent
                }
            }
            .background(.black)
            .navigationTitle("share.scan.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .accessibilityIdentifier("share-scanner-full-screen")
    }

    private var unavailableContent: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "share.scan.unavailable.title",
                systemImage: "camera.viewfinder",
                description: Text("share.scan.unavailable.message")
            )
            HStack {
                Button("action.retry", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderedProminent)
                Button("action.cancel", role: .cancel, action: dismiss.callAsFunction)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityIdentifier("share-scanner-unavailable")
    }

    private func retry() {
        model.retry(canAttemptScanning: availabilityMode.canAttemptScanning)
    }

    private func deliver(_ token: String) {
        onToken(token)
        dismiss()
    }
}

private struct ShareDataScanner: UIViewControllerRepresentable {
    let isApplicationActive: Bool
    let retryGeneration: Int
    let onWillStart: () -> Void
    let onStarted: () -> Void
    let onUnavailable: () -> Void
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            retryGeneration: retryGeneration,
            onWillStart: onWillStart,
            onStarted: onStarted,
            onUnavailable: onUnavailable,
            onToken: onToken
        )
    }

    func makeUIViewController(context: Context) -> ShareScannerHostViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return ShareScannerHostViewController(
            scanner: scanner,
            isApplicationActive: isApplicationActive,
            onWillStart: onWillStart,
            onStarted: onStarted,
            onUnavailable: onUnavailable
        )
    }

    func updateUIViewController(_ controller: ShareScannerHostViewController, context: Context) {
        context.coordinator.update(
            retryGeneration: retryGeneration,
            onWillStart: onWillStart,
            onStarted: onStarted,
            onUnavailable: onUnavailable,
            onToken: onToken
        )
        controller.updateCallbacks(
            onWillStart: onWillStart,
            onStarted: onStarted,
            onUnavailable: onUnavailable
        )
        controller.setApplicationActive(isApplicationActive)
        if context.coordinator.consumeRetry(retryGeneration) {
            controller.retry()
        }
    }

    static func dismantleUIViewController(
        _ controller: ShareScannerHostViewController,
        coordinator: Coordinator
    ) {
        controller.stop()
        controller.scanner.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private var lastRetryGeneration: Int
        private var onWillStart: () -> Void
        private var onStarted: () -> Void
        private var onUnavailable: () -> Void
        private var onToken: (String) -> Void
        private var delivered = false

        init(
            retryGeneration: Int,
            onWillStart: @escaping () -> Void,
            onStarted: @escaping () -> Void,
            onUnavailable: @escaping () -> Void,
            onToken: @escaping (String) -> Void
        ) {
            lastRetryGeneration = retryGeneration
            self.onWillStart = onWillStart
            self.onStarted = onStarted
            self.onUnavailable = onUnavailable
            self.onToken = onToken
        }

        func update(
            retryGeneration: Int,
            onWillStart: @escaping () -> Void,
            onStarted: @escaping () -> Void,
            onUnavailable: @escaping () -> Void,
            onToken: @escaping (String) -> Void
        ) {
            self.onWillStart = onWillStart
            self.onStarted = onStarted
            self.onUnavailable = onUnavailable
            self.onToken = onToken
        }

        func consumeRetry(_ generation: Int) -> Bool {
            guard generation != lastRetryGeneration else { return false }
            lastRetryGeneration = generation
            return true
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard delivered == false else { return }
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue,
                    let token = try? StrictShareScannedPayloadParser().parseScannedPayload(payload)
                else {
                    continue
                }
                delivered = true
                onToken(token)
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onUnavailable()
        }
    }
}

@MainActor
private final class ShareScannerHostViewController: UIViewController {
    let scanner: DataScannerViewController
    private var applicationActive: Bool
    private var visible = false
    private var scanning = false
    private var onWillStart: () -> Void
    private var onStarted: () -> Void
    private var onUnavailable: () -> Void

    init(
        scanner: DataScannerViewController,
        isApplicationActive: Bool,
        onWillStart: @escaping () -> Void,
        onStarted: @escaping () -> Void,
        onUnavailable: @escaping () -> Void
    ) {
        self.scanner = scanner
        applicationActive = isApplicationActive
        self.onWillStart = onWillStart
        self.onStarted = onStarted
        self.onUnavailable = onUnavailable
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        startIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        stop()
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        stopScanning()
        onWillStart()
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.startIfPossible()
        }
    }

    func updateCallbacks(
        onWillStart: @escaping () -> Void,
        onStarted: @escaping () -> Void,
        onUnavailable: @escaping () -> Void
    ) {
        self.onWillStart = onWillStart
        self.onStarted = onStarted
        self.onUnavailable = onUnavailable
    }

    func setApplicationActive(_ active: Bool) {
        guard active != applicationActive else { return }
        applicationActive = active
        if active {
            startIfPossible()
        } else {
            stopScanning()
            onWillStart()
        }
    }

    func retry() {
        stopScanning()
        startIfPossible()
    }

    func stop() {
        visible = false
        stopScanning()
    }

    private func startIfPossible() {
        guard visible, applicationActive, scanning == false else { return }
        onWillStart()
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            onUnavailable()
            return
        }
        do {
            try scanner.startScanning()
            scanning = true
            onStarted()
        } catch {
            scanning = false
            onUnavailable()
        }
    }

    private func stopScanning() {
        guard scanning else { return }
        scanner.stopScanning()
        scanning = false
    }
}
