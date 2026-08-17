#if os(iOS) && canImport(CoreMotion)
    import CoreMotion
    import Foundation
    import MauryaEffects
    import UIKit

    public enum CoreMotionCoordinateMapper {
        /// Core Motion reports accelerometer reaction force; Android's sensor
        /// fixture uses the opposite gravity convention. Negating all axes makes
        /// a face-up stationary phone map from iOS z=-1 g to Android z=+1 g.
        public static func androidAcceleration(_ value: CMAcceleration) -> Vector3 {
            Vector3(x: -value.x, y: -value.y, z: -value.z)
        }

        public static func androidGyroscope(_ value: CMRotationRate) -> Vector3 {
            Vector3(x: value.x, y: value.y, z: value.z)
        }
    }

    private enum MotionEvent: Sendable {
        case acceleration(Vector3, Int64)
        case gyroscope(Vector3, Int64)
        case attitude(Attitude, Int64)
        case pressure(Double, Int64)
        case proximity(Bool, Int64)
        case failure(Set<RuntimeInputKey>)
    }

    public actor CoreMotionInputProvider {
        private static let accelerationKeys: Set<RuntimeInputKey> = [
            .sensorAccelX, .sensorAccelY, .sensorAccelZ, .sensorMotion, .sensorShake,
        ]
        private static let gyroscopeKeys: Set<RuntimeInputKey> = [
            .sensorGyroX, .sensorGyroY, .sensorGyroZ,
        ]
        private static let attitudeKeys: Set<RuntimeInputKey> = [
            .sensorPitch, .sensorRoll, .sensorYaw, .sensorHeading,
        ]
        private static let environmentKeys: Set<RuntimeInputKey> = [
            .sensorLight, .sensorNear, .sensorPressure,
        ]

        private let hub: AnalysisInputHub
        private let manager: CMMotionManager
        private let altimeter = CMAltimeter()
        private let operationQueue: OperationQueue
        private var analyzer = MotionAnalyzer()
        private var consumer: Task<Void, Never>?
        private var continuation: AsyncStream<MotionEvent>.Continuation?
        private var proximityTask: Task<Void, Never>?

        public init(hub: AnalysisInputHub) {
            self.hub = hub
            manager = CMMotionManager()
            operationQueue = OperationQueue()
            operationQueue.name = "Maurya.CoreMotion"
            operationQueue.qualityOfService = .userInteractive
            operationQueue.maxConcurrentOperationCount = 1
        }

        public func start(required: Set<RuntimeInputKey>, hertz: Double = 30) async {
            await stop(markStopped: false)
            let interval = 1 / min(max(hertz, 10), 60)
            let pair = AsyncStream.makeStream(
                of: MotionEvent.self,
                bufferingPolicy: .bufferingNewest(8)
            )
            continuation = pair.continuation
            consumer = Task { [weak self] in
                for await event in pair.stream {
                    guard Task.isCancelled == false else { break }
                    await self?.consume(event)
                }
            }

            let acceleration = required.intersection(Self.accelerationKeys)
            if acceleration.isEmpty == false {
                if manager.isAccelerometerAvailable {
                    manager.accelerometerUpdateInterval = interval
                    manager.startAccelerometerUpdates(to: operationQueue) { data, error in
                        guard let value = data?.acceleration, error == nil else {
                            pair.continuation.yield(.failure(acceleration)); return
                        }
                        pair.continuation.yield(
                            .acceleration(
                                CoreMotionCoordinateMapper.androidAcceleration(value),
                                AnalysisClock.monotonicMilliseconds()
                            ))
                    }
                } else {
                    pair.continuation.yield(.failure(acceleration))
                }
            }

            let gyroscope = required.intersection(Self.gyroscopeKeys)
            if gyroscope.isEmpty == false {
                if manager.isGyroAvailable {
                    manager.gyroUpdateInterval = interval
                    manager.startGyroUpdates(to: operationQueue) { data, error in
                        guard let value = data?.rotationRate, error == nil else {
                            pair.continuation.yield(.failure(gyroscope)); return
                        }
                        pair.continuation.yield(
                            .gyroscope(
                                CoreMotionCoordinateMapper.androidGyroscope(value),
                                AnalysisClock.monotonicMilliseconds()
                            ))
                    }
                } else {
                    pair.continuation.yield(.failure(gyroscope))
                }
            }

            let attitude = required.intersection(Self.attitudeKeys)
            if attitude.isEmpty == false {
                if manager.isDeviceMotionAvailable {
                    let frames = CMMotionManager.availableAttitudeReferenceFrames()
                    let frame: CMAttitudeReferenceFrame =
                        frames.contains(.xArbitraryCorrectedZVertical)
                        ? .xArbitraryCorrectedZVertical : .xArbitraryZVertical
                    manager.deviceMotionUpdateInterval = interval
                    manager.startDeviceMotionUpdates(using: frame, to: operationQueue) { data, error in
                        guard let value = data?.attitude, error == nil else {
                            pair.continuation.yield(.failure(attitude)); return
                        }
                        pair.continuation.yield(
                            .attitude(
                                Attitude(
                                    pitchRadians: value.pitch,
                                    rollRadians: value.roll,
                                    yawRadians: value.yaw
                                ),
                                AnalysisClock.monotonicMilliseconds()
                            ))
                    }
                } else {
                    pair.continuation.yield(.failure(attitude))
                }
            }

            if required.contains(.sensorPressure) {
                if CMAltimeter.isRelativeAltitudeAvailable() {
                    await hub.setLatchedInputsActive([.sensorPressure], active: true, at: AnalysisClock.monotonicMilliseconds())
                    altimeter.startRelativeAltitudeUpdates(to: operationQueue) { data, error in
                        guard let pressure = data?.pressure.doubleValue, error == nil else {
                            pair.continuation.yield(.failure([.sensorPressure])); return
                        }
                        pair.continuation.yield(
                            .pressure(
                                CoreMotionEnvironmentMapper.androidPressure(kilopascals: pressure),
                                AnalysisClock.monotonicMilliseconds()
                            ))
                    }
                } else {
                    pair.continuation.yield(.failure([.sensorPressure]))
                }
            }

            if required.contains(.sensorNear) {
                proximityTask = Task { @MainActor [hub] in
                    let device = UIDevice.current
                    device.isProximityMonitoringEnabled = true
                    guard device.isProximityMonitoringEnabled else {
                        pair.continuation.yield(.failure([.sensorNear])); return
                    }
                    await hub.setLatchedInputsActive(
                        [.sensorNear],
                        active: true,
                        at: AnalysisClock.monotonicMilliseconds()
                    )
                    pair.continuation.yield(
                        .proximity(
                            device.proximityState,
                            AnalysisClock.monotonicMilliseconds()
                        ))
                    for await _ in NotificationCenter.default.notifications(
                        named: UIDevice.proximityStateDidChangeNotification
                    ) {
                        guard Task.isCancelled == false else { break }
                        pair.continuation.yield(
                            .proximity(
                                device.proximityState,
                                AnalysisClock.monotonicMilliseconds()
                            ))
                    }
                }
            }

            if required.contains(.sensorLight) {
                await hub.mark(
                    [.sensorLight],
                    unavailable: .unsupported,
                    permission: .notRequired,
                    at: AnalysisClock.monotonicMilliseconds()
                )
            }
        }

        public func zeroAttitude() {
            analyzer.zeroAttitude()
        }

        public func stop() async {
            await stop(markStopped: true)
        }

        private func stop(markStopped: Bool) async {
            manager.stopAccelerometerUpdates()
            manager.stopGyroUpdates()
            manager.stopDeviceMotionUpdates()
            altimeter.stopRelativeAltitudeUpdates()
            proximityTask?.cancel()
            proximityTask = nil
            await MainActor.run { UIDevice.current.isProximityMonitoringEnabled = false }
            continuation?.finish()
            continuation = nil
            consumer?.cancel()
            consumer = nil
            await hub.setLatchedInputsActive(
                [.sensorNear, .sensorPressure],
                active: false,
                at: AnalysisClock.monotonicMilliseconds()
            )
            if markStopped {
                await hub.mark(
                    Self.accelerationKeys.union(Self.gyroscopeKeys).union(Self.attitudeKeys).union(Self.environmentKeys),
                    unavailable: .stopped,
                    permission: .notRequired,
                    at: AnalysisClock.monotonicMilliseconds()
                )
            }
        }

        private func consume(_ event: MotionEvent) async {
            let updates: [RuntimeInputKey: AnalysisInputSample]
            let now: Int64
            switch event {
            case let .acceleration(value, timestamp):
                now = timestamp
                updates = analyzer.analyzeAcceleration(value, timestampMilliseconds: timestamp)
            case let .gyroscope(value, timestamp):
                now = timestamp
                updates = analyzer.analyzeGyroscope(value, timestampMilliseconds: timestamp)
            case let .attitude(value, timestamp):
                now = timestamp
                updates = analyzer.analyzeAttitude(value, timestampMilliseconds: timestamp)
            case let .pressure(value, timestamp):
                now = timestamp
                updates = [
                    .sensorPressure: AnalysisInputSample(
                        value: .number(value), updatedAtMilliseconds: timestamp
                    )
                ]
            case let .proximity(value, timestamp):
                now = timestamp
                updates = [
                    .sensorNear: AnalysisInputSample(
                        value: .number(CoreMotionEnvironmentMapper.androidNear(value)),
                        updatedAtMilliseconds: timestamp
                    )
                ]
            case let .failure(keys):
                await hub.setLatchedInputsActive(
                    keys,
                    active: false,
                    at: AnalysisClock.monotonicMilliseconds()
                )
                await hub.mark(
                    keys,
                    unavailable: .unsupported,
                    permission: .notRequired,
                    at: AnalysisClock.monotonicMilliseconds()
                )
                return
            }
            await hub.updatePhysical(updates, at: now)
        }
    }
#endif
