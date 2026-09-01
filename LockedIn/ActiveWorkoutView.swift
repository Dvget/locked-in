import SwiftUI
import SwiftData
import Combine
import UIKit
import AudioToolbox

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    let state: ActiveWorkoutState
    let onFinished: () -> Void

    @State private var slotIndex = 0
    @State private var selectedExerciseIDs: [Int: String]
    @State private var weight: Double = 20
    @State private var reps = 10
    @State private var remainingSeconds = 150
    @State private var timerRunning = false
    @State private var timerEndDate: Date?
    @State private var workoutSets: [SetRecord] = []
    @State private var showFinishScreen = false
    @State private var showAbortConfirmation = false
    @State private var editingSet: SetRecord?

    @AppStorage("heavyRestSeconds") private var heavyRestSeconds: Double = 150
    @AppStorage("lightRestSeconds") private var lightRestSeconds: Double = 120

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(state: ActiveWorkoutState, onFinished: @escaping () -> Void) {
        self.state = state
        self.onFinished = onFinished
        _slotIndex = State(initialValue: min(max(state.slotIndex, 0), ExerciseCatalog.slots.count - 1))
        _selectedExerciseIDs = State(initialValue: state.exerciseIDsBySlot)
    }

    private var slot: PlanSlotDefinition {
        ExerciseCatalog.slots[slotIndex]
    }

    private var exercise: ExerciseDefinition {
        let id = selectedExerciseIDs[slot.id] ?? slot.defaultExerciseID
        return slot.exercises.first(where: { $0.id == id }) ?? slot.defaultExercise
    }

    private var currentExerciseSets: [SetRecord] {
        workoutSets
            .filter { $0.planSlot == slot.id && $0.exerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private var nextSetNumber: Int {
        currentExerciseSets.count + 1
    }

    private var previous: [SetRecord] {
        previousSets(for: exercise.id)
    }

    private var defaultRestSeconds: Int {
        slotIndex < 4 ? Int(heavyRestSeconds) : Int(lightRestSeconds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    exerciseHeader
                    timerSection
                    previousPerformanceCard
                    inputCard
                    primaryAction
                    skipSetAction
                    todaysSetsCard
                    previousExerciseButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .padding(.bottom, 16)
            }
            .background(Color.black)
            .toolbar { workoutToolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                fetchWorkoutSets()
                loadSuggestedValues()

                if let storedEnd = state.timerEndDate, storedEnd > Date() {
                    timerEndDate = storedEnd
                    remainingSeconds = max(0, Int(ceil(storedEnd.timeIntervalSinceNow)))
                    timerRunning = true
                    TimerNotificationManager.schedule(endDate: storedEnd)
                } else {
                    resetTimerForCurrentExercise()
                }

                persistSession()
                LiveActivityManager.startOrUpdate(
                    workoutID: state.workoutID,
                    startedAt: state.startedAt,
                    exerciseName: exercise.name,
                    restEndDate: timerEndDate
                )
            }
            .onReceive(timer) { _ in updateTimerFromClock() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncFromLiveActivity()
                    updateTimerFromClock()
                }
            }
            .sheet(item: $editingSet) { set in
                EditSetSheet(
                    record: set,
                    repsOnly: exercise.repsOnly,
                    increment: exercise.dumbbellIncrement ? 2 : 2.5
                ) {
                    fetchWorkoutSets()
                }
            }
            .sheet(isPresented: $showFinishScreen) {
                FinishWorkoutSheet(
                    duration: Date().timeIntervalSince(state.startedAt),
                    volume: workoutSets.reduce(0) { $0 + $1.volume },
                    setCount: workoutSets.count,
                    exerciseCount: Set(workoutSets.map(\.planSlot)).count,
                    onFinish: {
                        showFinishScreen = false
                        finishWorkout()
                    },
                    onBack: {
                        showFinishScreen = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .alert("Training abbrechen?", isPresented: $showAbortConfirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Training löschen", role: .destructive) { abortWorkout() }
            } message: {
                Text("Das laufende Training und alle darin gespeicherten Sätze werden gelöscht.")
            }
        }
    }

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Übung \(slotIndex + 1) von \(ExerciseCatalog.slots.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.lockedGreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timerSection: some View {
        LockedCard {
            VStack(spacing: 6) {
                HStack {
                    Text("Gesamtzeit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(state.startedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                RestTimerView(
                remainingSeconds: $remainingSeconds,
                isRunning: $timerRunning,
                defaultSeconds: defaultRestSeconds,
                subtract30: { adjustTimer(by: -30) },
                skip: skipTimer,
                reset: resetTimerForCurrentExercise,
                add30: { adjustTimer(by: 30) }
                )
            }
        }
    }

    private var previousPerformanceCard: some View {
        LockedCard {
            PreviousPerformanceView(
                sets: previous,
                targetSetNumber: min(max(nextSetNumber, 1), 3),
                repsOnly: exercise.repsOnly
            )
        }
    }

    private var inputCard: some View {
        HStack(spacing: 12) {
            if !exercise.repsOnly {
                ValueControlCard(
                    title: "GEWICHT",
                    value: weight.cleanWeight,
                    unit: "kg",
                    minus: { weight = max(0, weight - weightStep) },
                    plus: { weight += weightStep }
                )
            }

            ValueControlCard(
                title: "WIEDERHOLUNGEN",
                value: "\(reps)",
                unit: "reps",
                minus: { reps = max(0, reps - 1) },
                plus: { reps += 1 }
            )
        }
    }

    @ViewBuilder
    private var todaysSetsCard: some View {
        if !currentExerciseSets.isEmpty {
            LockedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEUTIGE SÄTZE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lockedGreen)

                    ForEach(currentExerciseSets, id: \.id) { set in
                        CurrentSetRow(
                            set: set,
                            repsOnly: exercise.repsOnly,
                            edit: { editingSet = set },
                            delete: { deleteSet(set) }
                        )

                        if set.id != currentExerciseSets.last?.id {
                            Divider().overlay(Color.lockedBorder)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previousExerciseButton: some View {
        if slotIndex > 0 {
            Button {
                cancelTimerNotification()
                timerRunning = false
                timerEndDate = nil
                slotIndex -= 1
                resetTimerForCurrentExercise()
                loadSuggestedValues()
                persistSession()
                LiveActivityManager.startOrUpdate(
                    workoutID: state.workoutID,
                    startedAt: state.startedAt,
                    exerciseName: exercise.name,
                    restEndDate: timerEndDate
                )
            } label: {
                Label("Zur vorherigen Übung", systemImage: "chevron.left")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(LockedActionButtonStyle())
        }
    }

    @ViewBuilder
    private var skipSetAction: some View {
        if currentExerciseSets.count < 3 {
            Button {
                saveSet(repsOverride: 0)
            } label: {
                Label("Satz überspringen · 0 Wiederholungen", systemImage: "forward.end")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(LockedActionButtonStyle())
        }
    }

    private var primaryAction: some View {
        Button {
            if currentExerciseSets.count >= 3 {
                advanceWorkout()
            } else {
                saveSet()
            }
        } label: {
            HStack {
                Spacer()
                Text(primaryActionTitle)
                    .font(.headline)
                Spacer()
                Image(systemName: currentExerciseSets.count >= 3 ? "chevron.right" : "checkmark")
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
        }
        .buttonStyle(LockedActionButtonStyle(prominent: true))
    }

    private var primaryActionTitle: String {
        if currentExerciseSets.count >= 3 {
            return slotIndex == ExerciseCatalog.slots.count - 1 ? "Training abschließen" : "Weiter zur nächsten Übung"
        }
        return "Satz \(nextSetNumber) speichern"
    }

    private var weightStep: Double {
        exercise.dumbbellIncrement ? 2 : 2.5
    }

    @ToolbarContentBuilder
    private var workoutToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            EmptyView()
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu("Übung anpassen") {
                    ForEach(slot.exercises) { candidate in
                        Button {
                            selectedExerciseIDs[slot.id] = candidate.id
                            loadSuggestedValues()
                            persistSession()
                            LiveActivityManager.startOrUpdate(
                                workoutID: state.workoutID,
                                startedAt: state.startedAt,
                                exerciseName: candidate.name,
                                restEndDate: timerEndDate
                            )
                        } label: {
                            if candidate.id == exercise.id {
                                Label(candidate.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.name)
                            }
                        }
                    }
                }

                Divider()

                Button("Training abbrechen", role: .destructive) {
                    showAbortConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func startRestTimer() {
        cancelTimerNotification()
        remainingSeconds = defaultRestSeconds
        timerEndDate = Date().addingTimeInterval(TimeInterval(defaultRestSeconds))
        timerRunning = true
        persistSession()
        if let timerEndDate {
            TimerNotificationManager.schedule(endDate: timerEndDate)
        }
        LiveActivityManager.startOrUpdate(
            workoutID: state.workoutID,
            startedAt: state.startedAt,
            exerciseName: exercise.name,
            restEndDate: timerEndDate
        )
    }

    private func updateTimerFromClock() {
        guard timerRunning, let timerEndDate else { return }
        let seconds = max(0, Int(ceil(timerEndDate.timeIntervalSinceNow)))
        remainingSeconds = seconds

        if seconds <= 0 {
            timerRunning = false
            self.timerEndDate = nil
            TimerNotificationManager.cancel()
            persistSession()
            LiveActivityManager.startOrUpdate(
                workoutID: state.workoutID,
                startedAt: state.startedAt,
                exerciseName: exercise.name,
                restEndDate: nil
            )

            if scenePhase == .active {
                signalTimerFinished()
            }
        }
    }

    private func syncFromLiveActivity() {
        guard let liveState = LiveActivityManager.timerState(workoutID: state.workoutID) else { return }

        if liveState.isPaused {
            cancelTimerNotification()
            timerRunning = false
            timerEndDate = nil
            remainingSeconds = max(0, liveState.pausedRemainingSeconds)
            persistSession()
            return
        }

        if let end = liveState.restEndDate, end > Date() {
            timerEndDate = end
            remainingSeconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
            timerRunning = true
            persistSession()
        }
    }

    private func signalTimerFinished() {
        RestTimerAudioAlert.shared.play()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func adjustTimer(by seconds: Int) {
        if timerRunning, let end = timerEndDate {
            let newEnd = end.addingTimeInterval(TimeInterval(seconds))
            if newEnd <= Date() {
                skipTimer()
                return
            }
            timerEndDate = newEnd
            remainingSeconds = max(0, Int(ceil(newEnd.timeIntervalSinceNow)))
            persistSession()
            TimerNotificationManager.schedule(endDate: newEnd)
            LiveActivityManager.startOrUpdate(
                workoutID: state.workoutID,
                startedAt: state.startedAt,
                exerciseName: exercise.name,
                restEndDate: timerEndDate
            )
        } else {
            remainingSeconds = max(0, remainingSeconds + seconds)
        }
    }

    private func skipTimer() {
        cancelTimerNotification()
        timerRunning = false
        timerEndDate = nil
        remainingSeconds = 0
        persistSession()
        LiveActivityManager.startOrUpdate(
            workoutID: state.workoutID,
            startedAt: state.startedAt,
            exerciseName: exercise.name,
            restEndDate: nil
        )
    }

    private func resetTimerForCurrentExercise() {
        cancelTimerNotification()
        timerRunning = false
        timerEndDate = nil
        remainingSeconds = defaultRestSeconds
        persistSession()
        LiveActivityManager.startOrUpdate(
            workoutID: state.workoutID,
            startedAt: state.startedAt,
            exerciseName: exercise.name,
            restEndDate: nil
        )
    }

    private func cancelTimerNotification() {
        TimerNotificationManager.cancel()
    }

    private func saveSet(repsOverride: Int? = nil) {
        timerRunning = false
        timerEndDate = nil

        let record = SetRecord(
            workoutID: state.workoutID,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            planSlot: slot.id,
            setNumber: nextSetNumber,
            weight: exercise.repsOnly ? 0 : weight,
            reps: repsOverride ?? reps,
            rir: nil
        )
        modelContext.insert(record)
        try? modelContext.save()
        fetchWorkoutSets()
        persistSession()
        startRestTimer()
    }

    private func deleteSet(_ set: SetRecord) {
        modelContext.delete(set)
        try? modelContext.save()
        fetchWorkoutSets()

        for (index, item) in currentExerciseSets.enumerated() {
            item.setNumber = index + 1
        }
        try? modelContext.save()
        fetchWorkoutSets()
    }

    private func advanceWorkout() {
        cancelTimerNotification()
        timerRunning = false
        timerEndDate = nil

        if slotIndex == ExerciseCatalog.slots.count - 1 {
            showFinishScreen = true
        } else {
            slotIndex += 1
            resetTimerForCurrentExercise()
            loadSuggestedValues()
            persistSession()
            LiveActivityManager.startOrUpdate(
                workoutID: state.workoutID,
                startedAt: state.startedAt,
                exerciseName: exercise.name,
                restEndDate: nil
            )
        }
    }

    private func fetchWorkoutSets() {
        let id = state.workoutID
        let descriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { $0.workoutID == id },
            sortBy: [SortDescriptor(\SetRecord.completedAt)]
        )
        workoutSets = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func previousSets(for exerciseID: String) -> [SetRecord] {
        let currentWorkoutID = state.workoutID
        let descriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { item in
                item.exerciseID == exerciseID && item.workoutID != currentWorkoutID
            },
            sortBy: [SortDescriptor(\SetRecord.completedAt, order: .reverse)]
        )

        guard let all = try? modelContext.fetch(descriptor), let newest = all.first else {
            return []
        }

        let previousWorkoutID = newest.workoutID
        return all
            .filter { $0.workoutID == previousWorkoutID }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func loadSuggestedValues() {
        let values = previousSets(for: exercise.id)
        let target = min(currentExerciseSets.count, max(values.count - 1, 0))

        if !values.isEmpty {
            let previousSet = values[target]
            weight = previousSet.weight
            reps = previousSet.reps
        } else {
            weight = exercise.repsOnly ? 0 : 20
            reps = 10
        }
    }

    private func persistSession() {
        WorkoutSessionStore.save(
            ActiveWorkoutState(
                workoutID: state.workoutID,
                startedAt: state.startedAt,
                exerciseIDsBySlot: selectedExerciseIDs,
                slotIndex: slotIndex,
                timerEndDate: timerRunning ? timerEndDate : nil
            )
        )
    }

    private func finishWorkout() {
        cancelTimerNotification()
        WorkoutSessionStore.clear()
        LiveActivityManager.end()
        let workoutID = state.workoutID
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.id == workoutID }
        )

        if let workout = try? modelContext.fetch(descriptor).first {
            workout.endedAt = Date()
            workout.isCompleted = true
            try? modelContext.save()
            try? AutomaticBackup.backup(modelContext: modelContext)
        }
        onFinished()
    }

    private func abortWorkout() {
        cancelTimerNotification()
        WorkoutSessionStore.clear()
        LiveActivityManager.end()
        let workoutID = state.workoutID
        let setDescriptor = FetchDescriptor<SetRecord>(
            predicate: #Predicate { $0.workoutID == workoutID }
        )
        if let values = try? modelContext.fetch(setDescriptor) {
            values.forEach { modelContext.delete($0) }
        }

        let workoutDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.id == workoutID }
        )
        if let workout = try? modelContext.fetch(workoutDescriptor).first {
            modelContext.delete(workout)
        }
        try? modelContext.save()
        onFinished()
    }
}

private struct FinishWorkoutSheet: View {
    let duration: TimeInterval
    let volume: Double
    let setCount: Int
    let exerciseCount: Int
    let onFinish: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(Color.lockedGreen.opacity(0.14))
                            .frame(width: 92, height: 92)

                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.lockedGreen)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 7) {
                        Text("Training geschafft")
                            .font(.largeTitle.bold())

                        Text("Deine Session ist bereit zum Speichern.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        summaryCard(title: "DAUER", value: duration.shortDuration, icon: "clock.fill")
                        summaryCard(title: "VOLUMEN", value: "\(Int(volume).formatted()) kg", icon: "chart.bar.fill")
                    }

                    HStack(spacing: 12) {
                        summaryCard(title: "SÄTZE", value: "\(setCount)", icon: "list.number")
                        summaryCard(title: "ÜBUNGEN", value: "\(exerciseCount)", icon: "dumbbell.fill")
                    }

                    Button(action: onFinish) {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                            Text("Training speichern & abschließen")
                            Spacer()
                        }
                        .font(.headline)
                        .frame(height: 62)
                    }
                    .buttonStyle(LockedActionButtonStyle(prominent: true))
                    .padding(.top, 8)

                    Button(action: onBack) {
                        Label("Zurück zum Training", systemImage: "chevron.left")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(LockedActionButtonStyle())
                }
                .padding(20)
            }
        }
    }

    private func summaryCard(title: String, value: String, icon: String) -> some View {
        LockedCard {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.lockedGreen)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PreviousPerformanceView: View {
    let sets: [SetRecord]
    let targetSetNumber: Int
    let repsOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LETZTES MAL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.lockedGreen)

            if sets.isEmpty {
                Text("Noch keine Daten für diese Variante")
                    .foregroundStyle(.secondary)
            } else {
                let target = sets.first(where: { $0.setNumber == targetSetNumber }) ?? sets.last!

                Text("Satz \(target.setNumber) letztes Mal")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.lockedGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.lockedGreen.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity)

                Text(mainText(target))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                HStack {
                    ForEach(sets.prefix(3), id: \.id) { set in
                        VStack(spacing: 4) {
                            Text("Satz \(set.setNumber)")
                                .font(.subheadline)
                                .foregroundStyle(set.setNumber == targetSetNumber ? Color.lockedGreen : .secondary)
                            Text(shortText(set))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(set.setNumber == targetSetNumber ? Color.lockedGreen : .primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func mainText(_ set: SetRecord) -> String {
        repsOnly ? "\(set.reps) reps" : "\(set.weight.cleanWeight) kg × \(set.reps)"
    }

    private func shortText(_ set: SetRecord) -> String {
        repsOnly ? "\(set.reps)" : "\(set.weight.cleanWeight) × \(set.reps)"
    }
}

private struct ValueControlCard: View {
    let title: String
    let value: String
    let unit: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        LockedCard {
            VStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.lockedGreen)

                Text(value)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    controlButton("minus", action: minus)
                    controlButton("plus", action: plus)
                }
            }
        }
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(LockedActionButtonStyle())
    }
}

private struct CurrentSetRow: View {
    let set: SetRecord
    let repsOnly: Bool
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(set.setNumber)")
                .foregroundStyle(Color.lockedGreen)
                .frame(width: 22)

            Text(repsOnly ? "\(set.reps) reps" : "\(set.weight.cleanWeight) kg × \(set.reps) reps")
                .font(.subheadline.monospacedDigit())

            Spacer()

            Button(action: edit) {
                Image(systemName: "pencil")
                    .frame(width: 36, height: 36)
            }

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 36, height: 36)
            }
        }
    }
}

private struct EditSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let record: SetRecord
    let repsOnly: Bool
    let increment: Double
    let onSaved: () -> Void

    @State private var weight: Double
    @State private var reps: Int

    init(record: SetRecord, repsOnly: Bool, increment: Double, onSaved: @escaping () -> Void) {
        self.record = record
        self.repsOnly = repsOnly
        self.increment = increment
        self.onSaved = onSaved
        _weight = State(initialValue: record.weight)
        _reps = State(initialValue: record.reps)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !repsOnly {
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
                        record.weight = repsOnly ? 0 : weight
                        record.reps = reps
                        try? modelContext.save()
                        onSaved()
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
