import Foundation

enum RunMath {
    static func paceSecondsPerKm(distanceMeters: Double, seconds: Int) -> Double? {
        guard distanceMeters > 0, seconds > 0 else { return nil }
        return Double(seconds) / (distanceMeters / 1000)
    }

    static func formatPace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite else { return "—" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func formatKm(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "es_ES"))) + " km"
    }
}
