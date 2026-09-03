import Combine
import CoreLocation
import Foundation
import UIKit

struct RunFinishedPayload {
    let runID: UUID
    let startedAt: Date
    let activeDurationSeconds: TimeInterval
    let pausedDurationSeconds: TimeInterval
    let metrics: RunMetricsSnapshot
    let configuration: RunTrackingConfiguration
    let archiveData: Data
}

@MainActor
final class RunTrackingEngine: NSObject, ObservableObject {
    let runID: UUID
    let configuration: RunTrackingConfiguration

    @Published private(set) var phase: RunSessionPhase
    @Published private(set) var metrics: RunMetricsSnapshot
    @Published private(set) var activeDurationSeconds: TimeInterval = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var gpsReady = false
    @Published private(set) var lastError: String?
    @Published var speechEnabled: Bool {
        didSet {
            UserDefaults.standard.set(speechEnabled, forKey: Self.speechPreferenceKey)
            checkpoint(force: true)
        }
    }

    var currentPaceSecondsPerKm: Double? {
        metrics.currentPaceSecondsPerKm
    }

    var averagePaceSecondsPerKm: Double? {
        guard metrics.distanceMeters > 0, activeDurationSeconds > 0 else { return nil }
        return activeDurationSeconds / (metrics.distanceMeters / 1_000)
    }

    var canStart: Bool {
        phase == .preparing && gpsReady && Self.isAuthorized(authorizationStatus)
    }

    private static let speechPreferenceKey = "runKilometreSpeechEnabled"
    private let locationManager = CLLocationManager()
    private let audioCoach = RunAudioCoach()
    private var clock: RunSessionClock
    private var calculator: RunMetricsCalculator
    private var timerTask: Task<Void, Never>?
    private var lastCheckpointAt = Date.distantPast
    private var announcedSplitCount = 0

    init(
        checkpoint: RunSessionCheckpoint? = nil,
        configuration: RunTrackingConfiguration = .version1
    ) {
        self.runID = checkpoint?.runID ?? UUID()
        self.configuration = configuration
        self.clock = checkpoint?.clock ?? RunSessionClock()
        self.calculator = checkpoint.map {
            RunMetricsCalculator(configuration: configuration, replaying: $0.metrics.route)
        } ?? RunMetricsCalculator(configuration: configuration)
        self.metrics = checkpoint?.metrics ?? .empty
        self.phase = checkpoint?.clock.phase ?? .preparing
        self.authorizationStatus = CLLocationManager().authorizationStatus
        self.speechEnabled = checkpoint?.speechEnabled
            ?? UserDefaults.standard.object(forKey: Self.speechPreferenceKey) as? Bool
            ?? true
        self.announcedSplitCount = checkpoint?.metrics.splits.count ?? 0
        super.init()
        self.activeDurationSeconds = clock.activeDuration(at: Date())
    }

    deinit {
        timerTask?.cancel()
    }

    static func restoreIfAvailable() -> RunTrackingEngine? {
        guard let checkpoint = RunSessionStore.load() else { return nil }
        return RunTrackingEngine(checkpoint: checkpoint)
    }

    func prepare() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        authorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if Self.isAuthorized(authorizationStatus) {
            locationManager.startUpdatingLocation()
        }
        startTimerIfNeeded()
    }

    func beginCountdown() -> Bool {
        guard canStart, clock.beginCountdown() else { return false }
        phase = clock.phase
        return true
    }

    func start(at date: Date = Date()) -> Bool {
        guard clock.start(at: date) else { return false }
        phase = clock.phase
        activeDurationSeconds = 0
        locationManager.startUpdatingLocation()
        startTimerIfNeeded()
        checkpoint(force: true)
        return true
    }

    func pause(at date: Date = Date()) -> Bool {
        guard clock.pause(at: date) else { return false }
        phase = clock.phase
        updateClock(at: date)
        checkpoint(force: true)
        return true
    }

    func resume(at date: Date = Date()) -> Bool {
        guard clock.resume(at: date) else { return false }
        phase = clock.phase
        updateClock(at: date)
        checkpoint(force: true)
        return true
    }

    func finish(at date: Date = Date()) throws -> RunFinishedPayload {
        guard clock.finish(at: date), let startedAt = clock.startedAt else {
            throw RunTrackingError.invalidState
        }
        phase = clock.phase
        updateClock(at: date)
        locationManager.stopUpdatingLocation()
        timerTask?.cancel()
        timerTask = nil
        audioCoach.stop()

        let metadata = RunDiagnosticMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            operatingSystem: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            recordedAt: date
        )
        let archive = NativeRunArchive(
            algorithmVersion: configuration.algorithmVersion,
            route: metrics.route,
            splits: metrics.splits,
            configuration: configuration,
            metadata: metadata
        )
        let archiveData = try RunArchiveCodec.encode(archive)
        checkpoint(force: true)

        return RunFinishedPayload(
            runID: runID,
            startedAt: startedAt,
            activeDurationSeconds: activeDurationSeconds,
            pausedDurationSeconds: clock.pausedDuration(at: date),
            metrics: metrics,
            configuration: configuration,
            archiveData: archiveData
        )
    }

    func markSaved() {
        _ = clock.markSaved()
        phase = clock.phase
        RunSessionStore.clear()
    }

    func discard() {
        _ = clock.discard()
        phase = clock.phase
        locationManager.stopUpdatingLocation()
        timerTask?.cancel()
        timerTask = nil
        audioCoach.stop()
        RunSessionStore.clear()
    }

    func toggleSpeech() {
        speechEnabled.toggle()
        if !speechEnabled {
            audioCoach.stop()
        }
    }

    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.updateClock(at: Date())
                self.checkpoint(force: false)
            }
        }
    }

    private func updateClock(at date: Date) {
        activeDurationSeconds = clock.activeDuration(at: date)
    }

    private func checkpoint(force: Bool) {
        guard [.recording, .paused].contains(clock.phase) else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheckpointAt) >= 10 else { return }
        lastCheckpointAt = now
        try? RunSessionStore.save(RunSessionCheckpoint(
            runID: runID,
            clock: clock,
            metrics: metrics,
            speechEnabled: speechEnabled,
            savedAt: now
        ))
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }
}

extension RunTrackingEngine: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            if Self.isAuthorized(manager.authorizationStatus) {
                manager.startUpdatingLocation()
                self.lastError = nil
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.lastError = "Standortzugriff ist für die Laufaufzeichnung erforderlich."
                self.gpsReady = false
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
        }
    }

    private func handle(_ locations: [CLLocation]) {
        let receivedAt = Date()
        for location in locations {
            let sample = RunLocationSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                reportedSpeed: location.speed
            )

            let readiness = RunLocationFilter(configuration: configuration).evaluate(
                sample,
                receivedAt: receivedAt,
                previousAccepted: nil
            )
            if readiness.accepted {
                gpsReady = true
                lastError = nil
            }

            guard phase == .recording || phase == .paused else { continue }
            let previousSplitCount = metrics.splits.count
            metrics = calculator.ingest(
                sample,
                receivedAt: receivedAt,
                isPaused: phase == .paused
            )

            if speechEnabled, metrics.splits.count > previousSplitCount {
                for split in metrics.splits.dropFirst(announcedSplitCount) {
                    let average = averagePaceSecondsPerKm ?? split.paceSecondsPerKm
                    audioCoach.announceCompletedKilometre(
                        split.kilometre,
                        averagePaceSecondsPerKm: average
                    )
                }
                announcedSplitCount = metrics.splits.count
            }
            checkpoint(force: false)
        }
    }
}

enum RunTrackingError: LocalizedError {
    case invalidState

    var errorDescription: String? {
        "Der Lauf befindet sich nicht in einem speicherbaren Zustand."
    }
}
