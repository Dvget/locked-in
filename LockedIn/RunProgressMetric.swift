import Foundation

enum RunProgressMetric {
    struct Point {
        let date: Date
        let distanceKm: Double
        let paceSecondsPerKm: Double
        let distanceIndex: Double
        let paceIndex: Double
        let overallIndex: Double
    }

    static func points(for runs: [RunRecord]) -> [Point] {
        let valid = runs
            .filter { $0.distanceKm > 0 && $0.durationSeconds > 0 }
            .sorted { $0.date < $1.date }

        guard let baseline = valid.first else { return [] }
        let baselineDistance = max(0.01, baseline.distanceKm)
        let baselinePace = max(1, baseline.paceSecondsPerKm)

        return valid.map { run in
            let distanceIndex = (run.distanceKm / baselineDistance) * 100
            let paceIndex = (baselinePace / max(1, run.paceSecondsPerKm)) * 100
            let overall = sqrt(max(0.01, distanceIndex) * max(0.01, paceIndex))

            return Point(
                date: run.date,
                distanceKm: run.distanceKm,
                paceSecondsPerKm: run.paceSecondsPerKm,
                distanceIndex: distanceIndex,
                paceIndex: paceIndex,
                overallIndex: overall
            )
        }
    }

    static func changeFromBaseline(for runs: [RunRecord]) -> Double? {
        guard let last = points(for: runs).last else { return nil }
        return last.overallIndex - 100
    }

    static func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
