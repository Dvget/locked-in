import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var workouts: [WorkoutRecord]
    @Query private var runs: [RunRecord]
    @Query private var steps: [StepRecord]
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]

    private var completedStrength: Int {
        workouts.filter { $0.isCompleted && !$0.isHidden }.count
    }

    var body: some View {
        NavigationStack {
            EntryScreenLayout { cardHeight in
                NavigationLink {
                    StrengthStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .strength,
                        primary: "\(completedStrength) Trainings",
                        secondary: "Leistungsfortschritt in %",
                        accent: true,
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RunStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .runs,
                        primary: runs.isEmpty ? "Noch keine Daten" : "\(runs.count) Einträge",
                        secondary: "Laufstatistiken",
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StepStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .steps,
                        primary: steps.isEmpty ? "Noch keine Daten" : "\(steps.count) Einträge",
                        secondary: "Schrittstatistiken",
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WeightStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .weight,
                        primary: weights.first.map { "\($0.weightKg.cleanWeight) kg" } ?? "Noch keine Daten",
                        secondary: "Gewichtsstatistiken",
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Statistiken")
        }
    }
}
