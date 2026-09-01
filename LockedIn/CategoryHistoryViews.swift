import SwiftUI
import SwiftData

struct StrengthHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @State private var showAdd = false
    @State private var editingWorkout: WorkoutRecord?
    @State private var pendingDeleteWorkout: WorkoutRecord?

    private var completed: [WorkoutRecord] { workouts.filter(\.isCompleted) }

    var body: some View {
        List {
            ForEach(completed, id: \.id) { workout in
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Full Body").font(.headline)
                                if workout.isHidden {
                                    Image(systemName: "eye.slash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Dauer · \(workout.duration.shortDuration)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if workout.isHidden {
                            Text("Ausgeblendet")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            let progress = StrengthProgressMetric.workoutProgress(
                                workout: workout,
                                workouts: workouts,
                                sets: sets
                            )
                            Text(StrengthProgressMetric.text(progress))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(StrengthProgressStyle.color(for: progress))
                        }
                    }
                    .padding(.vertical, 8)
                    .opacity(workout.isHidden ? 0.55 : 1)
                }
                .contextMenu {
                    Button {
                        editingWorkout = workout
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }

                    Button {
                        workout.isHidden.toggle()
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                    } label: {
                        Label(
                            workout.isHidden ? "Einblenden" : "Ausblenden",
                            systemImage: workout.isHidden ? "eye" : "eye.slash"
                        )
                    }

                    Button(role: .destructive) {
                        pendingDeleteWorkout = workout
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Krafttraining")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ManualStrengthEntryView() }
        .sheet(item: $editingWorkout) { workout in
            TrainingEditSheet(workout: workout)
        }
        .alert("Training löschen?", isPresented: Binding(
            get: { pendingDeleteWorkout != nil },
            set: { if !$0 { pendingDeleteWorkout = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingDeleteWorkout = nil }
            Button("Löschen", role: .destructive) {
                if let workout = pendingDeleteWorkout {
                    deleteWorkout(workout)
                }
                pendingDeleteWorkout = nil
            }
        } message: {
            Text("Das Training und alle zugehörigen Sätze werden dauerhaft gelöscht.")
        }
        .lockedSwipeBack()
    }

    private func deleteWorkout(_ workout: WorkoutRecord) {
        sets.filter { $0.workoutID == workout.id }.forEach { modelContext.delete($0) }
        modelContext.delete(workout)
        try? modelContext.save()
        try? AutomaticBackup.backup(modelContext: modelContext)
    }
}

private struct ManualSetDraft: Identifiable {
    let id = UUID()
    var weight: Double = 20
    var reps: Int = 0
}

private struct ManualExerciseDraft: Identifiable {
    let id = UUID()
    var slotID: Int
    var exerciseID: String
    var sets: [ManualSetDraft] = [ManualSetDraft(), ManualSetDraft(), ManualSetDraft()]

    var completedSetCount: Int { sets.filter { $0.reps > 0 }.count }
}

struct ManualStrengthEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("manualBodyWeightKg") private var manualBodyWeightKg: Double = StrengthProgressMetric.fallbackBodyWeightKg
    @Query(sort: \WeightRecord.date, order: .reverse) private var weightRecords: [WeightRecord]

    @State private var date = Date()
    @State private var durationMinutes = 60
    @State private var showDatePicker = false
    @State private var drafts: [ManualExerciseDraft] = ExerciseCatalog.slots.map {
        ManualExerciseDraft(slotID: $0.id, exerciseID: $0.defaultExerciseID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LockedCard {
                        VStack(spacing: 12) {
                            Button {
                                showDatePicker = true
                            } label: {
                                HStack {
                                    Text("Datum")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(date.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider().overlay(Color.lockedBorder)

                            Stepper("Dauer: \(durationMinutes) Min.", value: $durationMinutes, in: 1...300)
                        }
                    }

                    ForEach(Array(drafts.indices), id: \.self) { index in
                        NavigationLink {
                            ManualExerciseEditorView(
                                draft: $drafts[index],
                                onSaveTraining: save
                            )
                        } label: {
                            manualExerciseRow(drafts[index])
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("Training nachtragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Trainingstag")
                    .presentationDetents([.medium])
            }
        }
    }

    private func manualExerciseRow(_ draft: ManualExerciseDraft) -> some View {
        let exercise = ExerciseCatalog.exercise(id: draft.exerciseID)
        return LockedCard {
            HStack(spacing: 14) {
                Text("\(draft.slotID)")
                    .font(.headline)
                    .foregroundStyle(Color.lockedGreen)
                    .frame(width: 34, height: 34)
                    .background(Color.lockedGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise?.name ?? "Übung")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(draft.completedSetCount == 0 ? "Noch keine Sätze eingetragen" : "\(draft.completedSetCount) Sätze eingetragen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
    }

    private var bodyWeightForManualWorkout: Double {
        weightRecords.first(where: { !$0.isHidden && $0.source == EtekcityScaleManager.sourceID })?.weightKg
            ?? manualBodyWeightKg
    }

    private func save() {
        let workout = WorkoutRecord(startedAt: date, bodyWeightSnapshot: bodyWeightForManualWorkout)
        workout.endedAt = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        workout.isCompleted = true
        modelContext.insert(workout)

        for draft in drafts {
            guard let exercise = ExerciseCatalog.exercise(id: draft.exerciseID) else { continue }
            for (index, item) in draft.sets.enumerated() where item.reps > 0 {
                modelContext.insert(SetRecord(
                    workoutID: workout.id,
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    planSlot: draft.slotID,
                    setNumber: index + 1,
                    weight: exercise.repsOnly ? 0 : max(0, item.weight),
                    reps: item.reps,
                    completedAt: date.addingTimeInterval(Double((draft.slotID * 10 + index) * 60))
                ))
            }
        }

        try? modelContext.save()
        try? AutomaticBackup.backup(modelContext: modelContext)
        dismiss()
    }
}

private struct ManualExerciseEditorView: View {
    @Binding var draft: ManualExerciseDraft
    let onSaveTraining: () -> Void

    private var slot: PlanSlotDefinition {
        ExerciseCatalog.slot(id: draft.slotID) ?? ExerciseCatalog.slots[0]
    }

    private var exercise: ExerciseDefinition {
        slot.exercises.first(where: { $0.id == draft.exerciseID }) ?? slot.defaultExercise
    }

    private var weightIncrement: Double {
        exercise.dumbbellIncrement ? 2 : 2.5
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ÜBUNG")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Menu {
                            ForEach(slot.exercises) { candidate in
                                Button {
                                    draft.exerciseID = candidate.id
                                    if candidate.repsOnly {
                                        for index in draft.sets.indices {
                                            draft.sets[index].weight = 0
                                        }
                                    }
                                } label: {
                                    if candidate.id == draft.exerciseID {
                                        Label(candidate.name, systemImage: "checkmark")
                                    } else {
                                        Text(candidate.name)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                    }
                }

                ForEach(Array(draft.sets.indices), id: \.self) { index in
                    setEditor(index: index)
                }

                Button {
                    draft.sets.append(ManualSetDraft(weight: exercise.repsOnly ? 0 : (draft.sets.last?.weight ?? 20), reps: 0))
                } label: {
                    Label("Satz hinzufügen", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(LockedActionButtonStyle())

                Button {
                    onSaveTraining()
                } label: {
                    Label("Speichern", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.lockedGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle(exercise.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    onSaveTraining()
                }
                .foregroundStyle(Color.lockedGreen)
                .fontWeight(.semibold)
            }
        }
        .lockedSwipeBack()
    }

    private func setEditor(index: Int) -> some View {
        LockedCard {
            VStack(spacing: 14) {
                HStack {
                    Text("SATZ \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lockedGreen)
                    Spacer()
                    if draft.sets.count > 1 {
                        Button(role: .destructive) {
                            draft.sets.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }

                if !exercise.repsOnly {
                    valueControl(
                        title: "GEWICHT",
                        value: "\(draft.sets[index].weight.cleanWeight) kg",
                        minus: { draft.sets[index].weight = max(0, draft.sets[index].weight - weightIncrement) },
                        plus: { draft.sets[index].weight = min(500, draft.sets[index].weight + weightIncrement) }
                    )
                }

                valueControl(
                    title: "WIEDERHOLUNGEN",
                    value: "\(draft.sets[index].reps)",
                    minus: { draft.sets[index].reps = max(0, draft.sets[index].reps - 1) },
                    plus: { draft.sets[index].reps = min(100, draft.sets[index].reps + 1) }
                )
            }
        }
    }

    private func valueControl(title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 10) {
                Button(action: minus) {
                    Image(systemName: "minus")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle())

                Button(action: plus) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle())
            }
        }
    }
}

private struct AutoDismissDatePicker: View {
    @Binding var date: Date
    @Binding var isPresented: Bool
    let title: String

    var body: some View {
        NavigationStack {
            DatePicker(
                title,
                selection: $date,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .padding()
            .onChange(of: date) {
                isPresented = false
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { isPresented = false }
                }
            }
        }
    }
}

struct RunHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]
    @State private var showAdd = false
    @State private var editingRun: RunRecord?
    @State private var pendingDeleteRun: RunRecord?

    var body: some View {
        List {
            ForEach(runs) { run in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Lauf").font(.headline)
                            if run.isHidden {
                                Image(systemName: "eye.slash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(run.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(run.distanceKm.cleanWeight) km · \(pace(run)) /km · \(formatDuration(run.durationSeconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if run.isHidden {
                        Text("Ausgeblendet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(pace(run))")
                            .font(.title3.bold().monospacedDigit())
                    }
                }
                .padding(.vertical, 8)
                .opacity(run.isHidden ? 0.55 : 1)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        editingRun = run
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }

                    Button {
                        run.isHidden.toggle()
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                    } label: {
                        Label(run.isHidden ? "Einblenden" : "Ausblenden", systemImage: run.isHidden ? "eye" : "eye.slash")
                    }

                    Button(role: .destructive) {
                        pendingDeleteRun = run
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Läufe")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ManualRunEntryView() }
        .sheet(item: $editingRun) { run in RunEditSheet(run: run) }
        .alert("Lauf löschen?", isPresented: Binding(
            get: { pendingDeleteRun != nil },
            set: { if !$0 { pendingDeleteRun = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingDeleteRun = nil }
            Button("Löschen", role: .destructive) {
                if let run = pendingDeleteRun {
                    modelContext.delete(run)
                    try? modelContext.save()
                    try? AutomaticBackup.backup(modelContext: modelContext)
                }
                pendingDeleteRun = nil
            }
        }
        .lockedSwipeBack()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private func pace(_ run: RunRecord) -> String {
        formatPace(run.paceSecondsPerKm)
    }
}

struct WeightHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightRecord.date, order: .reverse) private var records: [WeightRecord]
    @State private var showAdd = false
    @State private var editingWeight: WeightRecord?
    @State private var pendingDeleteWeight: WeightRecord?

    var body: some View {
        List {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(item.weightKg.cleanWeight) kg")
                                .font(.headline.monospacedDigit())
                            if item.isHidden {
                                Image(systemName: "eye.slash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(item.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if item.isHidden {
                        Text("Ausgeblendet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else if let delta = deltaForVisibleRecord(at: index) {
                        Text(signedWeight(delta))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(deltaColor(delta))
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .opacity(item.isHidden ? 0.55 : 1)
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        editingWeight = item
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }

                    Button {
                        item.isHidden.toggle()
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                    } label: {
                        Label(item.isHidden ? "Einblenden" : "Ausblenden", systemImage: item.isHidden ? "eye" : "eye.slash")
                    }

                    Button(role: .destructive) {
                        pendingDeleteWeight = item
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Gewicht")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ManualWeightEntryView() }
        .sheet(item: $editingWeight) { item in WeightEditSheet(record: item) }
        .alert("Messung löschen?", isPresented: Binding(
            get: { pendingDeleteWeight != nil },
            set: { if !$0 { pendingDeleteWeight = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingDeleteWeight = nil }
            Button("Löschen", role: .destructive) {
                if let item = pendingDeleteWeight {
                    modelContext.delete(item)
                    try? modelContext.save()
                    try? AutomaticBackup.backup(modelContext: modelContext)
                }
                pendingDeleteWeight = nil
            }
        }
        .lockedSwipeBack()
    }

    private func deltaForVisibleRecord(at index: Int) -> Double? {
        guard records.indices.contains(index), !records[index].isHidden else { return nil }
        let current = records[index]
        guard let older = records[(index + 1)...].first(where: { !$0.isHidden }) else { return nil }
        return current.weightKg - older.weightKg
    }

    private func signedWeight(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0,0 kg" }
        return String(format: "%+.1f kg", value).replacingOccurrences(of: ".", with: ",")
    }

    private func deltaColor(_ value: Double) -> Color {
        if value < -0.05 { return Color.lockedGreen }
        if value > 0.05 { return .red }
        return .yellow
    }
}

struct ManualRunEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date()
    @State private var distanceKm = 5.0
    @State private var paceText = "6:00"
    @State private var showDatePicker = false

    private var paceTotalSeconds: Int? { parsePace(paceText) }

    private var calculatedDuration: Double {
        max(0.01, distanceKm) * Double(paceTotalSeconds ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Button { showDatePicker = true } label: {
                    LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                }

                Section("Laufdaten") {
                    TextField("Distanz in km", value: $distanceKm, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)

                    TextField("Pace, z. B. 5:42", text: $paceText)
                        .keyboardType(.numbersAndPunctuation)
                        .monospacedDigit()

                    if paceTotalSeconds == nil {
                        Text("Pace bitte als Minuten:Sekunden eingeben, z. B. 5:42.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Lauf nachtragen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard paceTotalSeconds != nil else { return }
                        modelContext.insert(
                            RunRecord(
                                date: date,
                                distanceKm: max(0.01, distanceKm),
                                durationSeconds: calculatedDuration
                            )
                        )
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                    .disabled(paceTotalSeconds == nil || distanceKm <= 0)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Lauftag")
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct RunEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let run: RunRecord

    @State private var date: Date
    @State private var distanceKm: Double
    @State private var paceText: String
    @State private var showDatePicker = false

    init(run: RunRecord) {
        self.run = run
        _date = State(initialValue: run.date)
        _distanceKm = State(initialValue: run.distanceKm)
        _paceText = State(initialValue: formatPace(run.paceSecondsPerKm))
    }

    private var paceSeconds: Int? { parsePace(paceText) }

    var body: some View {
        NavigationStack {
            Form {
                Button { showDatePicker = true } label: {
                    LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                }

                TextField("Distanz in km", value: $distanceKm, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)

                TextField("Pace, z. B. 5:42", text: $paceText)
                    .keyboardType(.numbersAndPunctuation)
                    .monospacedDigit()
            }
            .navigationTitle("Lauf bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let paceSeconds else { return }
                        run.date = date
                        run.distanceKm = max(0.01, distanceKm)
                        run.durationSeconds = run.distanceKm * Double(paceSeconds)
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                    .disabled(paceSeconds == nil || distanceKm <= 0)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Lauftag")
                    .presentationDetents([.medium])
            }
        }
    }
}

struct ManualStepEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date()
    @State private var steps = 8000
    @State private var showDatePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Button { showDatePicker = true } label: {
                    LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                TextField("Schritte", value: $steps, format: .number)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("Steps nachtragen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        modelContext.insert(StepRecord(date: date, steps: max(0, steps)))
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Tag")
                    .presentationDetents([.medium])
            }
        }
    }
}

struct ManualWeightEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightRecord.date, order: .reverse) private var records: [WeightRecord]

    @State private var date = Date()
    @State private var weightKg = 90.0
    @State private var showDatePicker = false
    @State private var seededWeight = false

    var body: some View {
        NavigationStack {
            Form {
                Button { showDatePicker = true } label: {
                    LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                TextField("Gewicht in kg", value: $weightKg, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Gewicht nachtragen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        modelContext.insert(WeightRecord(date: date, weightKg: max(20, weightKg)))
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !seededWeight else { return }
                seededWeight = true
                if let latest = records.first(where: { !$0.isHidden }) {
                    weightKg = latest.weightKg
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Wiegetag")
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct WeightEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let record: WeightRecord

    @State private var date: Date
    @State private var weightKg: Double
    @State private var showDatePicker = false

    init(record: WeightRecord) {
        self.record = record
        _date = State(initialValue: record.date)
        _weightKg = State(initialValue: record.weightKg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Button { showDatePicker = true } label: {
                    LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                TextField("Gewicht in kg", value: $weightKg, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Gewicht bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        record.date = date
                        record.weightKg = max(20, weightKg)
                        try? modelContext.save()
                        try? AutomaticBackup.backup(modelContext: modelContext)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                AutoDismissDatePicker(date: $date, isPresented: $showDatePicker, title: "Wiegetag")
                    .presentationDetents([.medium])
            }
        }
    }
}

private func parsePace(_ text: String) -> Int? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = normalized.split(separator: ":")
    guard parts.count == 2,
          let minutes = Int(parts[0]),
          let seconds = Int(parts[1]),
          minutes >= 0,
          seconds >= 0,
          seconds < 60,
          minutes > 0 || seconds > 0 else { return nil }
    return minutes * 60 + seconds
}

private func formatPace(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
