import SwiftUI
import SwiftData

@main
struct LockedInApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            WorkoutRecord.self,
            SetRecord.self,
            RunRecord.self,
            StepRecord.self,
            WeightRecord.self
        ])

        let configuration = ModelConfiguration(
            "LockedInStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create LOCKED IN data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}