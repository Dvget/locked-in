import SwiftUI
import SwiftData

struct WorkoutPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("manualBodyWeightKg") private var manualBodyWeightKg: Double = StrengthProgressMetric.fallbackBodyWeightKg
    @Query(sort: \WeightRecord.date, order: .reverse) private var weightRecords: [WeightRecord]

    @State private var selectedExerciseIDs: [Int: String] = Dictionary(
        uniqueKeysWithValues: ExerciseCatalog.slots.map { ($0.id, $0.defaultExerciseID) }
    )
    @State private var activeWorkout: ActiveWorkoutState?
    private let onClose: (() -> Void)?
    private let onFlowFinished: (() -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onFlowFinished: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onFlowFinished = onFlowFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LIWordmark()

                    ForEach(ExerciseCatalog.slots) { slot in
                        WorkoutPlanRow(
                            slot: slot,
                            selectedExerciseID: selectedExerciseIDs[slot.id] ?? slot.defaultExerciseID,
                            onSelect: { selectedExerciseIDs[slot.id] = $0 }
                        )
                    }
                }
                .padding()
                .padding(.bottom, 90)
            }
            .background(Color.black)
            .safeAreaInset(edge: .bottom) {
                startButton
            }
            .navigationTitle("Dein Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                }
            }
            .fullScreenCover(item: $activeWorkout) { workoutState in
                ActiveWorkoutView(state: workoutState) {
                    activeWorkout = nil
                    if let onFlowFinished { onFlowFinished() } else { dismiss() }
                }
            }
        }
    }

    private var bodyWeightForNewWorkout: Double {
        weightRecords.first(where: { $0.source == EtekcityScaleManager.sourceID })?.weightKg
            ?? manualBodyWeightKg
    }

    private var startButton: some View {
        Button(action: startWorkout) {
            Label("Training starten", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
        }
        .buttonStyle(LockedActionButtonStyle(prominent: true))
        .padding()
        .background(.ultraThinMaterial)
    }

    private func startWorkout() {
        let workout = WorkoutRecord(bodyWeightSnapshot: bodyWeightForNewWorkout)
        modelContext.insert(workout)
        try? modelContext.save()

        let state = ActiveWorkoutState(
            workoutID: workout.id,
            startedAt: workout.startedAt,
            exerciseIDsBySlot: selectedExerciseIDs,
            slotIndex: 0,
            timerEndDate: nil
        )
        WorkoutSessionStore.save(state)
        activeWorkout = state
    }
}

private struct WorkoutPlanRow: View {
    let slot: PlanSlotDefinition
    let selectedExerciseID: String
    let onSelect: (String) -> Void

    private var selectedExercise: ExerciseDefinition {
        slot.exercises.first(where: { $0.id == selectedExerciseID }) ?? slot.defaultExercise
    }

    var body: some View {
        LockedCard {
            HStack(spacing: 12) {
                Text("\(slot.id)")
                    .font(.headline)
                    .foregroundStyle(Color.lockedGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.lockedGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedExercise.name).font(.headline)
                    Text("3 Sätze")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    ForEach(slot.exercises) { exercise in
                        Button {
                            onSelect(exercise.id)
                        } label: {
                            if exercise.id == selectedExerciseID {
                                Label(exercise.name, systemImage: "checkmark")
                            } else {
                                Text(exercise.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
            }
        }
    }
}

struct ActiveWorkoutState: Identifiable, Codable {
    var id: UUID { workoutID }
    let workoutID: UUID
    let startedAt: Date
    let exerciseIDsBySlot: [Int: String]
    let slotIndex: Int
    let timerEndDate: Date?
}
