import Foundation

enum WorkoutSessionStore {
    private static let key = "lockedIn.activeWorkoutState"

    static func save(_ state: ActiveWorkoutState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> ActiveWorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveWorkoutState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
