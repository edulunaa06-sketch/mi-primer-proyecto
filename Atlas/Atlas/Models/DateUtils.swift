import Foundation

/// Utilidades de fecha con semanas que empiezan en lunes (ISO 8601).
enum DateUtils {
    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // lunes
        cal.minimumDaysInFirstWeek = 4
        cal.locale = Locale(identifier: "es_ES")
        cal.timeZone = .current
        return cal
    }()

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Lunes 00:00 de la semana que contiene `date`.
    static func startOfWeek(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? startOfDay(date)
    }

    /// 1 = lunes … 7 = domingo.
    static func weekdayMondayBased(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = domingo en gregoriano
        return weekday == 1 ? 7 : weekday - 1
    }

    static func date(forWeekday weekday: Int, inWeekOf date: Date) -> Date {
        calendar.date(byAdding: .day, value: weekday - 1, to: startOfWeek(date)) ?? date
    }

    /// Clave estable para una semana, p. ej. "2026-10-19".
    static func weekKey(_ date: Date) -> String {
        dayKey(startOfWeek(date))
    }

    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// «2026-10-22» → fecha (inicio del día). nil si el texto no es una fecha válida.
    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func yearMonth(_ date: Date) -> (year: Int, month: Int) {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 0, c.month ?? 0)
    }

    static func monthTitle(year: Int, month: Int) -> String {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = calendar.date(from: comps) else { return "\(month)/\(year)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_ES")))
    }

    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
    }
}

enum NumberFormat {
    static func kg(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "es_ES")))
    }

    static func signedKg(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "−" : "±")
        return sign + kg(abs(value)) + " kg"
    }

    static func integer(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(Locale(identifier: "es_ES")))
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "es_ES")))
    }

    /// Peso de un disco o una carga, con hasta dos decimales: 80 → «80», 2,5 → «2,5», 1,25 → «1,25».
    /// Un decimal no basta: los discos de 1,25 kg se quedarían en «1,2».
    static func plate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_ES")))
    }

    /// Peso con su unidad y sin decimales de adorno: 80 → «80 kg», 1,25 → «1,25 kg».
    static func weight(_ value: Double) -> String { plate(value) + " kg" }

    static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "es_ES")))
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Acepta coma o punto como separador decimal.
    static func parseDecimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}
