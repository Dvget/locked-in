import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("coreMotionStepsEnabled") private var coreMotionStepsEnabled = false
    @AppStorage("lastAutomaticStepSync") private var lastAutomaticStepSync: Double = 0
    @State private var isSyncingPolar = false
    @State private var showWeeklyReport = false
    @AppStorage("lastPresentedWeeklyReport") private var lastPresentedWeeklyReport = ""

    private let minimumAutomaticSyncInterval: TimeInterval = 30 * 60

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Übersicht", systemImage: "house.fill") }

            WeeklyDevelopmentView()
                .tabItem { Label("Entwicklung", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .tint(.lockedGreen)
        .task {
            SeedData.insertIfNeeded(modelContext: modelContext)
            presentWeeklyReportIfNeeded()
            await syncPolar()
            await syncStepsIfNeeded(force: false)
        }
        .sheet(isPresented: $showWeeklyReport) {
            WeeklyDevelopmentView(reportOnly: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            presentWeeklyReportIfNeeded()
            Task {
                await syncPolar()
                await syncStepsIfNeeded(force: false)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1800))
                guard scenePhase == .active else { continue }
                await syncStepsIfNeeded(force: false)
            }
        }
    }

    @MainActor
    private func syncPolar() async {
        guard !isSyncingPolar else { return }
        isSyncingPolar = true
        defer { isSyncingPolar = false }

        do {
            _ = try await PolarRunSync.sync(modelContext: modelContext)
        } catch {
            // Polar is additive. Local data remains untouched and the next
            // foreground activation retries automatically.
        }
    }

    private func presentWeeklyReportIfNeeded() {
        let calendar = Calendar(identifier: .iso8601)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let key = "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
        guard key != lastPresentedWeeklyReport else { return }
        lastPresentedWeeklyReport = key
        showWeeklyReport = true
    }

    @MainActor
    private func syncStepsIfNeeded(force: Bool) async {
        guard coreMotionStepsEnabled else { return }

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastAutomaticStepSync

        guard force || lastAutomaticStepSync == 0 || elapsed >= minimumAutomaticSyncInterval else {
            return
        }

        do {
            _ = try await CoreMotionStepSync.syncLastSevenDays(modelContext: modelContext)
            lastAutomaticStepSync = now
        } catch {
            // Keep the last successful timestamp untouched so the next foreground
            // activation can retry automatically.
        }
    }
}
