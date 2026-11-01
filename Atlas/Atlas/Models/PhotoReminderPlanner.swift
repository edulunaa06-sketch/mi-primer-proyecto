import Foundation

/// Lógica pura para calcular las notificaciones de fotos (testeable sin UserNotifications).
enum PhotoReminderPlanner {
    static let idPrefix = "atlas.photos.monthly"

    struct Request: Equatable {
        let identifier: String
        let components: DateComponents
        let repeats: Bool
    }

    static func requests(referenceDay: Int, hour: Int, from now: Date, calendar: Calendar = DateUtils.calendar) -> [Request] {
        let day = min(max(referenceDay, 1), 31)
        if day <= 28 {
            var comps = DateComponents()
            comps.day = day
            comps.hour = hour
            comps.minute = 0
            return [Request(identifier: "\(idPrefix).repeating", components: comps, repeats: true)]
        }
        var result: [Request] = []
        for offset in 0..<12 {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: now),
                  let range = calendar.range(of: .day, in: .month, for: monthDate) else { continue }
            var comps = calendar.dateComponents([.year, .month], from: monthDate)
            comps.day = min(day, range.count)
            comps.hour = hour
            comps.minute = 0
            if let fire = calendar.date(from: comps), fire <= now { continue }
            let id = "\(idPrefix)." + String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            result.append(Request(identifier: id, components: comps, repeats: false))
        }
        return result
    }
}
