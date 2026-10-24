import Foundation

/// Fechas y días de la semana, siempre en español y empezando en lunes.
enum DateHelper {

    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "es_ES")
        cal.firstWeekday = 2 // lunes
        return cal
    }()

    static let locale = Locale(identifier: "es_ES")

    /// Medianoche del día de la fecha.
    static func startOfDay(_ date: Date = .now) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 1 = lunes ... 7 = domingo.
    static func weekdayIndex(_ date: Date = .now) -> Int {
        let sundayBased = calendar.component(.weekday, from: date) // 1 = domingo
        return ((sundayBased + 5) % 7) + 1
    }

    /// "Lunes", "Martes"...
    static func weekdayName(_ index: Int) -> String {
        let names = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
        guard (1...7).contains(index) else { return "" }
        return names[index - 1]
    }

    /// Abreviatura de tres letras: "Lun", "Mar"...
    static func weekdayShortName(_ index: Int) -> String {
        String(weekdayName(index).prefix(3))
    }

    /// Número de días desde una fecha de referencia (para variar los menús).
    static func dayNumber(_ date: Date) -> Int {
        let reference = Date(timeIntervalSince1970: 0)
        return calendar.dateComponents([.day], from: reference, to: startOfDay(date)).day ?? 0
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// "Hoy", "Ayer", "Mañana" o "Lunes 24 oct".
    static func friendlyName(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "Hoy" }
        if calendar.isDateInYesterday(date) { return "Ayer" }
        if calendar.isDateInTomorrow(date) { return "Mañana" }
        return longName(date)
    }

    /// "Lunes 24 oct"
    static func longName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date).capitalizedFirst
    }

    /// "24 oct 2026"
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    /// "24/10"
    static func dayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d/M"
        return formatter.string(from: date)
    }

    /// Segundos a "2:30" o "90 s".
    static func restText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        return rest == 0 ? "\(minutes) min" : String(format: "%d:%02d min", minutes, rest)
    }

    /// Segundos a "02:30" para el temporizador.
    static func timerText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}

extension String {
    /// Primera letra en mayúscula, el resto igual.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
