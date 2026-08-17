#if os(iOS) && canImport(AVFAudio)
    import AVFAudio
    import Foundation
    import MauryaEffects

    public enum AudioInputError: Error, Equatable, Sendable {
        case permissionDenied
        case noInputRoute
        case invalidInputFormat
    }

    private enum AudioInterruptionEvent: Sendable {
        case began
        case ended(shouldResume: Bool)
    }

    private nonisolated func installAnalysisTap(
        input: AVAudioInputNode,
        format: AVAudioFormat,
        ring: PCMRingBuffer
    ) {
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(AudioAnalyzer.frameSize), format: format) {
            buffer,
            _ in
            guard let channels = buffer.floatChannelData else { return }
            ring.appendMono(
                channels,
                channelCount: Int(buffer.format.channelCount),
                frameCount: Int(buffer.frameLength)
            )
        }
    }

    public actor AppleAudioInputProvider {
        public static let inputKeys: Set<RuntimeInputKey> = [
            .audioLevel, .audioPeak, .audioBass, .audioMid,
            .audioTreble, .audioBeat, .audioBPM,
        ]

        private let hub: AnalysisInputHub
        private let engine = AVAudioEngine()
        private let ring = PCMRingBuffer(capacity: AudioAnalyzer.frameSize * 64)
        private var analyzer = AudioAnalyzer()
        private var resampler = StreamingPCMResampler(inputSampleRate: 16_000)
        private var pendingAnalysisSamples: [Double] = []
        private var worker: Task<Void, Never>?
        private var notificationTasks: [Task<Void, Never>] = []
        private var isSessionRequested = false
        private var tapInstalled = false
        private var generation: UInt64 = 0

        public init(hub: AnalysisInputHub) {
            self.hub = hub
        }

        public func setSensitivity(_ value: Double) {
            analyzer.setSensitivity(value)
        }

        public func start() async throws {
            guard worker == nil else { return }
            generation &+= 1
            let startGeneration = generation
            isSessionRequested = true
            let permissionGranted = await AVAudioApplication.requestRecordPermission()
            guard generation == startGeneration, isSessionRequested else {
                throw CancellationError()
            }
            guard permissionGranted else {
                isSessionRequested = false
                await hub.mark(
                    Self.inputKeys,
                    unavailable: .permissionDenied,
                    permission: .denied,
                    at: AnalysisClock.monotonicMilliseconds()
                )
                throw AudioInputError.permissionDenied
            }
            do {
                try configureAndStartEngine()
            } catch {
                isSessionRequested = false
                if tapInstalled {
                    engine.inputNode.removeTap(onBus: 0)
                    tapInstalled = false
                }
                engine.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                await hub.mark(
                    Self.inputKeys,
                    unavailable: .routeUnavailable,
                    permission: .granted,
                    at: AnalysisClock.monotonicMilliseconds()
                )
                throw error
            }
            observeAudioSession()
            worker = Task { [weak self] in await self?.consumePCM() }
        }

        public func stop() async {
            generation &+= 1
            isSessionRequested = false
            worker?.cancel()
            worker = nil
            notificationTasks.forEach { $0.cancel() }
            notificationTasks.removeAll()
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            ring.clear()
            analyzer.reset()
            resampler.reset()
            pendingAnalysisSamples.removeAll(keepingCapacity: true)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            await hub.mark(
                Self.inputKeys,
                unavailable: .stopped,
                permission: .granted,
                at: AnalysisClock.monotonicMilliseconds()
            )
        }

        private func configureAndStartEngine() throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetoothHFP]
            )
            try session.setActive(true)
            guard session.isInputAvailable else { throw AudioInputError.noInputRoute }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate.isFinite,
                format.sampleRate > 0,
                format.channelCount > 0,
                format.commonFormat == .pcmFormatFloat32,
                format.isInterleaved == false
            else {
                throw AudioInputError.invalidInputFormat
            }
            resampler = StreamingPCMResampler(inputSampleRate: format.sampleRate)
            pendingAnalysisSamples.removeAll(keepingCapacity: true)
            installAnalysisTap(input: input, format: format, ring: ring)
            tapInstalled = true
            engine.prepare()
            try engine.start()
        }

        private func consumePCM() async {
            while Task.isCancelled == false {
                if let nativeSamples = ring.pop(upTo: AudioAnalyzer.frameSize * 4) {
                    pendingAnalysisSamples.append(contentsOf: resampler.append(nativeSamples))
                    while pendingAnalysisSamples.count >= AudioAnalyzer.frameSize {
                        let frame = Array(pendingAnalysisSamples.prefix(AudioAnalyzer.frameSize))
                        pendingAnalysisSamples.removeFirst(AudioAnalyzer.frameSize)
                        let now = AnalysisClock.monotonicMilliseconds()
                        let result = analyzer.analyze(frame, timestampMilliseconds: now)
                        await hub.updatePhysical(result.samples, at: now)
                    }
                } else {
                    try? await Task.sleep(for: .milliseconds(4))
                }
            }
        }

        private func observeAudioSession() {
            let interruptions = Task { [weak self] in
                for await note in NotificationCenter.default.notifications(
                    named: AVAudioSession.interruptionNotification
                ) {
                    guard Task.isCancelled == false else { break }
                    guard let event = Self.interruptionEvent(from: note) else { continue }
                    await self?.handleInterruption(event)
                }
            }
            let routes = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVAudioSession.routeChangeNotification
                ) {
                    guard Task.isCancelled == false else { break }
                    await self?.handleRouteChange()
                }
            }
            notificationTasks = [interruptions, routes]
        }

        private nonisolated static func interruptionEvent(
            from notification: Notification
        ) -> AudioInterruptionEvent? {
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return nil }
            if type == .began { return .began }
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            return .ended(shouldResume: shouldResume)
        }

        private func handleInterruption(_ event: AudioInterruptionEvent) async {
            switch event {
            case .began:
                engine.pause()
                await hub.mark(
                    Self.inputKeys,
                    unavailable: .interrupted,
                    permission: .granted,
                    at: AnalysisClock.monotonicMilliseconds()
                )
            case let .ended(shouldResume):
                guard shouldResume, isSessionRequested else { return }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try engine.start()
                } catch {
                    await hub.mark(
                        Self.inputKeys,
                        unavailable: .interrupted,
                        permission: .granted,
                        at: AnalysisClock.monotonicMilliseconds()
                    )
                }
            }
        }

        private func handleRouteChange() async {
            engine.pause()
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            ring.clear()
            resampler.reset()
            pendingAnalysisSamples.removeAll(keepingCapacity: true)
            await hub.mark(
                Self.inputKeys,
                unavailable: .routeUnavailable,
                permission: .granted,
                at: AnalysisClock.monotonicMilliseconds()
            )
            guard isSessionRequested else { return }
            do {
                try configureAndStartEngine()
            } catch {
                if tapInstalled {
                    engine.inputNode.removeTap(onBus: 0)
                    tapInstalled = false
                }
                engine.stop()
            }
        }
    }
#endif
