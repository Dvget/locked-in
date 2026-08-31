import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query private var workouts: [WorkoutRecord]
    @Query private var runs: [RunRecord]
    @Query private var steps: [StepRecord]

    private var completedStrength: Int {
        workouts.filter { $0.isCompleted }.count
    }

    var body: some View {
        NavigationStack {
            EntryScreenLayout(cardCount: 3) { cardHeight in
                NavigationLink {
                    StrengthHistoryView()
                } label: {
                    TrackingCategoryCard(
                        category: .strength,
                        primary: "\(completedStrength) Trainings",
                        secondary: "Krafttraining-Verlauf",
                        accent: true,
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RunHistoryView()
                } label: {
                    TrackingCategoryCard(
                        category: .runs,
                        primary: runs.isEmpty ? "Noch keine Einträge" : "\(runs.count) Läufe",
                        secondary: "Verlauf & manuell nachtragen",
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StepHistoryView()
                } label: {
                    TrackingCategoryCard(
                        category: .steps,
                        primary: steps.isEmpty ? "Noch keine Einträge" : "\(steps.count) Tage",
                        secondary: "Verlauf & manuell nachtragen",
                        minContentHeight: cardHeight
                    )
                }
                .buttonStyle(.plain)


            }
            .navigationTitle("Verlauf")
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutRecord
    @Query private var allSets: [SetRecord]
    @State private var editingSet: SetRecord?
    @State private var showDelete = false
    @State private var showEditTraining = false
    @State private var pendingDeleteSet: SetRecord?

    private var workoutSets: [SetRecord] {
        allSets.filter { $0.workoutID == workout.id }
            .sorted {
                $0.planSlot == $1.planSlot ? $0.setNumber < $1.setNumber : $0.planSlot < $1.planSlot
            }
    }

    var body: some View {
        List {
            if workout.isHidden {
                Section {
                    Label("Dieses Training ist ausgeblendet und wird in Statistiken und Auswertungen ignoriert.", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(ExerciseCatalog.slots) { slot in
                let slotSets = workoutSets.filter { $0.planSlot == slot.id }
                if !slotSets.isEmpty {
                    Section(slotSets.first?.exerciseName ?? slot.title) {
                        ForEach(slotSets, id: \.id) { set in
                            HStack {
                                Text("Satz \(set.setNumber)")
                                Spacer()
                                Text(setText(set))
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingSet = set
                            }
                            .contextMenu {
                                Button {
                                    editingSet = set
                                } label: {
                                    Label("Satz bearbeiten", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    pendingDeleteSet = set
                                } label: {
                                    Label("Satz löschen", systemImage: "trash")
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDeleteSet = set
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Training bearbeiten") { showEditTraining = true }

                    Button {
                        workout.isHidden.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(
                            workout.isHidden ? "Training einblenden" : "Dieses Training ausblenden",
                            systemImage: workout.isHidden ? "eye" : "eye.slash"
                        )
                    }

                    Button("Training löschen", role: .destructive) { showDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $editingSet) { set in
            HistorySetEditSheet(set: set)
        }
        .sheet(isPresented: $showEditTraining) {
            TrainingEditSheet(workout: workout)
        }
        .alert("Satz löschen?", isPresented: Binding(
            get: { pendingDeleteSet != nil },
            set: { if !$0 { pendingDeleteSet = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingDeleteSet = nil }
            Button("Satz löschen", role: .destructive) {
                if let set = pendingDeleteSet {
                    deleteSet(set)
                }
                pendingDeleteSet = nil
            }
        } message: {
            Text("Dieser Satz wird dauerhaft gelöscht. Gewicht und Wiederholungen können stattdessen über Bearbeiten geändert werden.")
        }
        .lockedSwipeBack()
        .alert("Training löschen?", isPresented: $showDelete) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { deleteTraining() }
        }
    }

    private func setText(_ set: SetRecord) -> String {
        let repsOnly = ExerciseCatalog.exercise(id: set.exerciseID)?.repsOnly ?? false
        return repsOnly ? "\(set.reps) reps" : "\(set.weight.cleanWeight) kg × \(set.reps)"
    }

    private func deleteSet(_ set: SetRecord) {
        let slot = set.planSlot
        let exerciseID = set.exerciseID
        let remaining = workoutSets
            .filter { $0.id != set.id && $0.planSlot == slot && $0.exerciseID == exerciseID }
            .sorted { $0.setNumber < $1.setNumber }

        modelContext.delete(set)
        for (index, item) in remaining.enumerated() {
            item.setNumber = index + 1
        }
        try? modelContext.save()
        try? AutomaticBackup.backup(modelContext: modelContext)
    }

    private func deleteTraining() {
        workoutSets.forEach { modelContext.delete($0) }
        modelContext.delete(workout)
        try? modelContext.save()
        dismiss()
    }
}

private struct HistorySetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let set: SetRecord
    @State private var weight: Double
    @State private var reps: Int

    init(set: SetRecord) {
        self.set = set
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }

    private var exercise: ExerciseDefinition? { ExerciseCatalog.exercise(id: set.exerciseID) }
    private var increment: Double { exercise?.dumbbellIncrement == true ? 2 : 2.5 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if exercise?.repsOnly != true {
                        editorCard(
                            title: "GEWICHT",
                            value: "\(weight.cleanWeight) kg",
                            minus: { weight = max(0, weight - increment) },
                            plus: { weight = min(500, weight + increment) }
                        )
                    }

                    editorCard(
                        title: "WIEDERHOLUNGEN",
                        value: "\(reps)",
                        minus: { reps = max(0, reps - 1) },
                        plus: { reps = min(100, reps + 1) }
                    )
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Satz bearbeiten")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        set.weight = exercise?.repsOnly == true ? 0 : weight
                        set.reps = reps
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func editorCard(
        title: String,
        value: String,
        minus: @escaping () -> Void,
        plus: @escaping () -> Void
    ) -> some View {
        LockedCard {
            VStack(spacing: 18) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lockedGreen)

                Text(value)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 12) {
                    editorButton("minus", action: minus)
                    editorButton("plus", action: plus)
                }
            }
        }
    }

    private func editorButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        }
        .buttonStyle(LockedActionButtonStyle())
    }
}

struct TrainingEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let workout: WorkoutRecord
    @State private var startedAt: Date
    @State private var endedAt: Date

    init(workout: WorkoutRecord) {
        self.workout = workout
        _startedAt = State(initialValue: workout.startedAt)
        _endedAt = State(initialValue: workout.endedAt ?? workout.startedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Beginn", selection: $startedAt)
                DatePicker("Ende", selection: $endedAt)
            }
            .navigationTitle("Training bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        workout.startedAt = startedAt
                        workout.endedAt = max(endedAt, startedAt)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
