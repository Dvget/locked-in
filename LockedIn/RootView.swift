import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("coreMotionStepsEnabled") private var coreMotionStepsEnabled = false
    @AppStorage("lastAutomaticStepSync") private var lastAutomaticStepSync: Double = 0

    private let minimumAutomaticSyncInterval: TimeInterval = 30 * 60

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Übersicht", systemImage: "house.fill") }

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .tint(.lockedGreen)
        .task {
            SeedData.insertIfNeeded(modelContext: modelContext)
            await syncStepsIfNeeded(force: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
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
