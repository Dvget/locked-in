import Foundation

struct RunTrackingConfiguration: Codable, Equatable {
    let algorithmVersion: String
    let maximumSampleAge: TimeInterval
    let maximumFutureOffset: TimeInterval
    let maximumHorizontalAccuracy: Double
    let maximumPlausibleSpeed: Double
    let rollingPaceWindow: TimeInterval
    let minimumPaceDistance: Double
    let elevationDeadband: Double

    static let version1 = RunTrackingConfiguration(
        algorithmVersion: "lockedIn-gps-v1",
        maximumSampleAge: 10,
        maximumFutureOffset: 1,
        maximumHorizontalAccuracy: 25,
        maximumPlausibleSpeed: 12,
        rollingPaceWindow: 30,
        minimumPaceDistance: 20,
        elevationDeadband: 3
    )
}

struct RunLocationSample: Codable, Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let reportedSpeed: Double
}

enum RunSampleRejectionReason: String, Codable, Equatable {
    case stale
    case future
    case invalidCoordinate
    case horizontalAccuracy
    case duplicate
    case nonIncreasingTime
    case implausibleSpeed
}

struct RunLocationDecision: Codable, Equatable {
    let sample: RunLocationSample
    let accepted: Bool
    let rejectionReason: RunSampleRejectionReason?
    let cumulativeDistanceMeters: Double
    let paused: Bool

    init(
        sample: RunLocationSample,
        accepted: Bool,
        rejectionReason: RunSampleRejectionReason? = nil,
        cumulativeDistanceMeters: Double = 0,
        paused: Bool = false
    ) {
        self.sample = sample
        self.accepted = accepted
        self.rejectionReason = rejectionReason
        self.cumulativeDistanceMeters = cumulativeDistanceMeters
        self.paused = paused
    }
}

struct RunSplit: Codable, Equatable, Identifiable {
    var id: Int { kilometre }
    let kilometre: Int
    let durationSeconds: TimeInterval
    let paceSecondsPerKm: Double
    let cumulativeDurationSeconds: TimeInterval
    let cumulativeDistanceMeters: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
}

struct RunMetricsSnapshot: Codable, Equatable {
    let distanceMeters: Double
    let activeDurationSeconds: TimeInterval
    let currentPaceSecondsPerKm: Double?
    let averagePaceSecondsPerKm: Double?
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let splits: [RunSplit]
    let route: [RunLocationDecision]

    static let empty = RunMetricsSnapshot(
        distanceMeters: 0,
        activeDurationSeconds: 0,
        currentPaceSecondsPerKm: nil,
        averagePaceSecondsPerKm: nil,
        elevationGainMeters: 0,
        elevationLossMeters: 0,
        splits: [],
        route: []
    )
}

struct RunLocationFilter {
    let configuration: RunTrackingConfiguration

    func evaluate(
        _ sample: RunLocationSample,
        receivedAt: Date,
        previousAccepted: RunLocationSample?
    ) -> RunLocationDecision {
        let age = receivedAt.timeIntervalSince(sample.timestamp)
        if age > configuration.maximumSampleAge {
            return rejected(sample, .stale)
        }
        if age < -configuration.maximumFutureOffset {
            return rejected(sample, .future)
        }
        guard (-90...90).contains(sample.latitude),
              (-180...180).contains(sample.longitude),
              sample.latitude.isFinite,
              sample.longitude.isFinite else {
            return rejected(sample, .invalidCoordinate)
        }
        guard sample.horizontalAccuracy > 0,
              sample.horizontalAccuracy <= configuration.maximumHorizontalAccuracy else {
            return rejected(sample, .horizontalAccuracy)
        }

        if let previousAccepted {
            let elapsed = sample.timestamp.timeIntervalSince(previousAccepted.timestamp)
            let identicalCoordinate = sample.latitude == previousAccepted.latitude
                && sample.longitude == previousAccepted.longitude

            if elapsed == 0, identicalCoordinate {
                return rejected(sample, .duplicate)
            }
            guard elapsed > 0 else {
                return rejected(sample, .nonIncreasingTime)
            }

            let distance = Self.distanceMeters(from: previousAccepted, to: sample)
            if distance / elapsed > configuration.maximumPlausibleSpeed {
                return rejected(sample, .implausibleSpeed)
            }
        }

        return RunLocationDecision(sample: sample, accepted: true)
    }

    private func rejected(
        _ sample: RunLocationSample,
        _ reason: RunSampleRejectionReason
    ) -> RunLocationDecision {
        RunLocationDecision(sample: sample, accepted: false, rejectionReason: reason)
    }

    static func distanceMeters(from first: RunLocationSample, to second: RunLocationSample) -> Double {
        let earthRadius = 6_371_000.0
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(firstLatitude) * cos(secondLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct RunMetricsCalculator {
    private struct PaceSegment {
        let endedAt: Date
        let distanceMeters: Double
        let durationSeconds: TimeInterval
    }

    let configuration: RunTrackingConfiguration
    private let filter: RunLocationFilter
    private var route: [RunLocationDecision] = []
    private var splits: [RunSplit] = []
    private var previousAccepted: RunLocationSample?
    private var previousActive: RunLocationSample?
    private var wasPaused = false
    private var distanceMeters = 0.0
    private var activeDurationSeconds: TimeInterval = 0
    private var elevationGainMeters = 0.0
    private var elevationLossMeters = 0.0
    private var lastElevationReference: Double?
    private var paceSegments: [PaceSegment] = []
    private var lastSplitDuration: TimeInterval = 0
    private var lastSplitGain = 0.0
    private var lastSplitLoss = 0.0

    init(configuration: RunTrackingConfiguration = .version1) {
        self.configuration = configuration
        self.filter = RunLocationFilter(configuration: configuration)
    }

    init(
        configuration: RunTrackingConfiguration = .version1,
        replaying decisions: [RunLocationDecision]
    ) {
        self.init(configuration: configuration)
        for decision in decisions {
            if decision.accepted {
                _ = ingestAccepted(
                    decision.sample,
                    isPaused: decision.paused,
                    persistedDecision: decision
                )
            } else {
                route.append(decision)
            }
        }
    }

    var currentSnapshot: RunMetricsSnapshot {
        snapshot()
    }

    mutating func beginPause() {
        previousActive = nil
        lastElevationReference = nil
        paceSegments.removeAll()
        wasPaused = true
    }

    mutating func endPause() {
        previousActive = nil
        lastElevationReference = nil
        paceSegments.removeAll()
        wasPaused = false
    }

    mutating func ingest(
        _ sample: RunLocationSample,
        receivedAt: Date = Date(),
        isPaused: Bool
    ) -> RunMetricsSnapshot {
        let evaluation = filter.evaluate(
            sample,
            receivedAt: receivedAt,
            previousAccepted: previousAccepted
        )

        guard evaluation.accepted else {
            route.append(RunLocationDecision(
                sample: sample,
                accepted: false,
                rejectionReason: evaluation.rejectionReason,
                cumulativeDistanceMeters: distanceMeters,
                paused: isPaused
            ))
            return snapshot()
        }

        return ingestAccepted(sample, isPaused: isPaused)
    }

    private mutating func ingestAccepted(
        _ sample: RunLocationSample,
        isPaused: Bool,
        persistedDecision: RunLocationDecision? = nil
    ) -> RunMetricsSnapshot {
        previousAccepted = sample

        if isPaused {
            route.append(persistedDecision ?? RunLocationDecision(
                sample: sample,
                accepted: true,
                cumulativeDistanceMeters: distanceMeters,
                paused: true
            ))
            beginPause()
            return snapshot()
        }

        if wasPaused {
            endPause()
        }

        let distanceBeforeSegment = distanceMeters
        let durationBeforeSegment = activeDurationSeconds
        var segmentDistance = 0.0
        var segmentDuration: TimeInterval = 0

        if let previousActive {
            segmentDuration = sample.timestamp.timeIntervalSince(previousActive.timestamp)
            if segmentDuration > 0 {
                segmentDistance = RunLocationFilter.distanceMeters(from: previousActive, to: sample)
                distanceMeters += segmentDistance
                activeDurationSeconds += segmentDuration
                paceSegments.append(PaceSegment(
                    endedAt: sample.timestamp,
                    distanceMeters: segmentDistance,
                    durationSeconds: segmentDuration
                ))
                updateElevation(with: sample.altitude)
                createCompletedSplits(
                    distanceBeforeSegment: distanceBeforeSegment,
                    durationBeforeSegment: durationBeforeSegment,
                    segmentDistance: segmentDistance,
                    segmentDuration: segmentDuration
                )
            }
        } else {
            lastElevationReference = sample.altitude
        }

        self.previousActive = sample
        trimPaceSegments(at: sample.timestamp)
        route.append(persistedDecision ?? RunLocationDecision(
            sample: sample,
            accepted: true,
            cumulativeDistanceMeters: distanceMeters,
            paused: false
        ))
        return snapshot()
    }

    private mutating func updateElevation(with altitude: Double) {
        guard altitude.isFinite else { return }
        guard let reference = lastElevationReference else {
            lastElevationReference = altitude
            return
        }
        let difference = altitude - reference
        guard abs(difference) >= configuration.elevationDeadband else { return }
        if difference > 0 {
            elevationGainMeters += difference
        } else {
            elevationLossMeters += abs(difference)
        }
        lastElevationReference = altitude
    }

    private mutating func createCompletedSplits(
        distanceBeforeSegment: Double,
        durationBeforeSegment: TimeInterval,
        segmentDistance: Double,
        segmentDuration: TimeInterval
    ) {
        guard segmentDistance > 0 else { return }
        var nextKilometre = splits.count + 1
        var boundary = Double(nextKilometre) * 1_000

        while distanceMeters >= boundary {
            let distanceIntoSegment = boundary - distanceBeforeSegment
            let fraction = min(1, max(0, distanceIntoSegment / segmentDistance))
            let boundaryDuration = durationBeforeSegment + segmentDuration * fraction
            let splitDuration = boundaryDuration - lastSplitDuration
            let splitGain = elevationGainMeters - lastSplitGain
            let splitLoss = elevationLossMeters - lastSplitLoss
            splits.append(RunSplit(
                kilometre: nextKilometre,
                durationSeconds: splitDuration,
                paceSecondsPerKm: splitDuration,
                cumulativeDurationSeconds: boundaryDuration,
                cumulativeDistanceMeters: boundary,
                elevationGainMeters: splitGain,
                elevationLossMeters: splitLoss
            ))
            lastSplitDuration = boundaryDuration
            lastSplitGain = elevationGainMeters
            lastSplitLoss = elevationLossMeters
            nextKilometre += 1
            boundary = Double(nextKilometre) * 1_000
        }
    }

    private mutating func trimPaceSegments(at timestamp: Date) {
        let cutoff = timestamp.addingTimeInterval(-configuration.rollingPaceWindow)
        paceSegments.removeAll { $0.endedAt < cutoff }
    }

    private func snapshot() -> RunMetricsSnapshot {
        let rollingDistance = paceSegments.reduce(0) { $0 + $1.distanceMeters }
        let rollingDuration = paceSegments.reduce(0) { $0 + $1.durationSeconds }
        let currentPace: Double? = rollingDistance >= configuration.minimumPaceDistance && rollingDuration > 0
            ? rollingDuration / (rollingDistance / 1_000)
            : nil
        let averagePace: Double? = distanceMeters > 0 && activeDurationSeconds > 0
            ? activeDurationSeconds / (distanceMeters / 1_000)
            : nil

        return RunMetricsSnapshot(
            distanceMeters: distanceMeters,
            activeDurationSeconds: activeDurationSeconds,
            currentPaceSecondsPerKm: currentPace,
            averagePaceSecondsPerKm: averagePace,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            splits: splits,
            route: route
        )
    }
}
