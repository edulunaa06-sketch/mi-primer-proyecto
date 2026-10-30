import SwiftData
import SwiftUI

/// Calendario mensual tipo mapa de calor: cada día coloreado según lo cumplido.
/// Al tocar un día se puede marcar como descanso, entrenado, enfermo o trabajando.
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query private var meals: [MealRecord]
    @Query private var logs: [WorkoutSessionLog]
    @Query private var dailySteps: [DailySteps]
    @Query private var marks: [DayMarkRecord]
    @Query private var settingsList: [UserSettings]

    @State private var month = CalendarView.startOfMonth(Date())
    @State private var selected: SelectedDay?
    @State private var trackingStart = DateUtils.startOfDay(Date())

    struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    static func startOfMonth(_ date: Date) -> Date {
        let ym = DateUtils.yearMonth(date)
        return DateUtils.calendar.date(from: DateComponents(year: ym.year, month: ym.month, day: 1)) ?? DateUtils.startOfDay(date)
    }

    /// Se calcula una vez (y de nuevo solo si cambian los datos), no en cada redibujado.
    @State private var snapshot: TrackingSnapshot?
    @State private var streak = Streak.Result(current: 0, best: 0)

    private var signature: String {
        TrackingSnapshot.signature(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                   stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
    }

    private var monthDays: [Date] {
        guard let next = DateUtils.calendar.date(byAdding: .month, value: 1, to: month),
              let last = DateUtils.calendar.date(byAdding: .day, value: -1, to: next) else { return [] }
        var days: [Date] = []
        var day = month
        while day <= last, days.count < 32 {
            days.append(day)
            guard let next = DateUtils.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard(streak)
                    if let snapshot {
                        monthCard(snapshot)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 300).card()
                    }
                    legend
                    InfoBanner(text: "Un día está cumplido con el \(Int(DayEvaluator.doneThreshold * 100)) % o más del cumplimiento diario (comidas, entreno del día y pasos). Descanso, enfermo y trabajando no cuentan como fallo ni rompen la racha; entrenado cuenta como día cumplido. Los viernes son descanso salvo que lo cambies.",
                               symbol: "info.circle.fill", color: Theme.lime)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Calendario")
            .onAppear { trackingStart = DataStore.trackingStart(context) }
            .task(id: signature) {
                let snap = TrackingSnapshot(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                            stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
                streak = snap.streak
                snapshot = snap
            }
            .sheet(item: $selected) { day in
                if let snap = snapshot {
                    DayMarkSheet(date: day.date, input: snap.input(for: day.date), outcome: snap.outcome(for: day.date))
                }
            }
        }
    }

    private func streakCard(_ streak: Streak.Result) -> some View {
        HStack(spacing: 12) {
            MetricTile(title: "Racha actual", value: Medals.days(Double(streak.current)),
                       detail: streak.current > 0 ? "Días cumplidos seguidos" : "Cumple hoy para empezarla", symbol: "flame.fill",
                       symbolColor: streak.current > 0 ? Theme.flame : Theme.textTertiary)
            MetricTile(title: "Mejor racha", value: Medals.days(Double(streak.best)), detail: "Desde que usas la app", symbol: "trophy.fill", symbolColor: Theme.gold)
        }
    }

    private func monthCard(_ snap: TrackingSnapshot) -> some View {
        let days = monthDays
        let outcomes = days.map(snap.outcome(for:))
        let leading = (days.first.map(DateUtils.weekdayMondayBased) ?? 1) - 1
        let isCurrentMonth = month == Self.startOfMonth(Date())
        return VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
                    .accessibilityLabel("Mes anterior")
                Spacer()
                let ym = DateUtils.yearMonth(month)
                Text(DateUtils.monthTitle(year: ym.year, month: ym.month)).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").font(.headline) }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Mes siguiente")
            }
            .foregroundStyle(Theme.lime)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
                // Huecos antes del día 1 con ids negativos: si repitieran los de los días (0, 1, 2…),
                // la cuadrícula se saltaría los primeros días del mes.
                ForEach(Array(stride(from: -1, through: -leading, by: -1)), id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(days.indices, id: \.self) { i in
                    let day = days[i]
                    let outcome = outcomes[i]
                    Button { selected = SelectedDay(date: day) } label: {
                        DayCell(date: day, outcome: outcome, isToday: DateUtils.calendar.isDateInToday(day))
                    }
                    .buttonStyle(.plain)
                    .disabled(outcome == .future)
                }
            }

            HStack {
                countLabel(outcomes.filter(\.isDone).count, "cumplidos", Theme.lime)
                Spacer()
                countLabel(outcomes.filter(\.isExcused).count, "descanso/libres", Theme.textSecondary)
                Spacer()
                countLabel(outcomes.filter(\.isMissed).count, "fallados", Theme.danger)
            }
            .font(.caption)
        }
        .card()
    }

    private func countLabel(_ n: Int, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(n)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(text).foregroundStyle(Theme.textSecondary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Leyenda")
            HStack(spacing: 14) {
                swatch(DayCell.color(for: .done(0.75)), "Cumplido")
                swatch(DayCell.color(for: .done(1)), "100 %")
                swatch(DayCell.color(for: .missed(0.3)), "Fallado")
            }
            HStack(spacing: 14) {
                ForEach([DayMark.rest, .trained, .sick, .work]) { mark in
                    HStack(spacing: 4) {
                        Image(systemName: mark.symbol).font(.caption2)
                        Text(mark == .sick ? "Enfermo" : mark.label).font(.caption2)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Toca un día para ver el detalle y marcarlo.").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    private func swatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 16, height: 16)
            Text(text).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = DateUtils.calendar.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation { month = Self.startOfMonth(next) }
    }
}

/// Casilla de un día: color según lo cumplido e icono si está marcado.
struct DayCell: View {
    let date: Date
    let outcome: DayOutcome
    var isToday = false
    var height: CGFloat = 40

    static func color(for outcome: DayOutcome) -> Color {
        switch outcome {
        case .trained: return Theme.lime
        case .done(let f):
            let t = min(max((f - DayEvaluator.doneThreshold) / (1 - DayEvaluator.doneThreshold), 0), 1)
            return Theme.lime.opacity(0.45 + 0.55 * t)
        case .today(let f): return Theme.lime.opacity(0.08 + 0.25 * f)
        case .missed(let f): return Theme.danger.opacity(0.18 + 0.3 * (1 - f))
        case .excused: return Theme.rest.opacity(0.30)
        case .future, .beforeStart: return Theme.card
        }
    }

    private var isBright: Bool {
        switch outcome {
        case .trained: return true
        case .done(let f): return f >= 0.85
        default: return false
        }
    }

    private var symbol: String? {
        switch outcome {
        case .trained: return DayMark.trained.symbol
        case .excused(let mark): return mark.symbol
        default: return nil
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(outcome == .future || outcome == .beforeStart ? Theme.cardRaised.opacity(0.5) : Self.color(for: outcome))
            Text("\(DateUtils.calendar.component(.day, from: date))")
                .font(.footnote.weight(isToday ? .heavy : .semibold).monospacedDigit())
                .foregroundStyle(isBright ? Theme.onLime : (outcome == .future ? Theme.textTertiary : Theme.textPrimary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isBright ? Theme.onLime : Theme.textSecondary)
                    .padding(3)
            }
        }
        .frame(height: height)
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.lime, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let day = DateUtils.shortDate(date)
        switch outcome {
        case .trained: return "\(day): entrenado"
        case .done(let f): return "\(day): cumplido \(NumberFormat.percent(f))"
        case .today(let f): return "\(day): hoy, \(NumberFormat.percent(f))"
        case .missed(let f): return "\(day): fallado \(NumberFormat.percent(f))"
        case .excused(let m): return "\(day): \(m.label.lowercased())"
        case .future: return "\(day): futuro"
        case .beforeStart: return "\(day): antes de empezar"
        }
    }
}

/// Detalle de un día y selector de marca (también para varios días seguidos).
struct DayMarkSheet: View {
    let date: Date
    let input: DayInput
    let outcome: DayOutcome

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var choice: DayMark = .normal
    @State private var until = Date()

    private var weekday: Int { DateUtils.weekdayMondayBased(date) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Comidas", value: "\(input.mealsCompleted)/4")
                    LabeledContent("Entreno", value: input.sessionsScheduled == 0 ? "Sin entreno programado" : "\(input.sessionsCompleted)/\(input.sessionsScheduled) sesiones")
                    LabeledContent("Pasos", value: input.steps.map { "\(NumberFormat.integer($0)) de \(NumberFormat.integer(input.stepGoal))" } ?? "Sin datos")
                    LabeledContent("Cumplimiento", value: NumberFormat.percent(DayEvaluator.compliance(input).fraction))
                    LabeledContent("Estado", value: statusText)
                } header: {
                    Text(sentenceCase(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES")))))
                }

                Section {
                    ForEach(DayMark.allCases) { mark in
                        Button { choice = mark } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mark.symbol).foregroundStyle(Theme.lime).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mark.label).foregroundStyle(Theme.textPrimary)
                                    Text(description(mark)).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if choice == mark {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.lime)
                                }
                            }
                        }
                        .accessibilityLabel(mark.label)
                        .accessibilityAddTraits(choice == mark ? .isSelected : [])
                    }
                } header: {
                    Text("Marcar el día")
                }

                Section {
                    DatePicker("Hasta", selection: $until, in: date..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "es_ES"))
                } footer: {
                    Text("Para marcar varios días seguidos (por ejemplo, si has estado malo), elige hasta qué día. Se aplica la misma marca a todos.")
                }
            }
            .screenBackground()
            .navigationTitle("Día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        DataStore.setMark(choice, from: date, through: max(until, date), in: context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                choice = DayMark.effective(explicit: input.explicitMark, weekday: weekday)
                until = date
            }
        }
        .presentationDetents([.large])
    }

    private var statusText: String {
        switch outcome {
        case .trained: return "Entrenado (cumplido)"
        case .done: return "Cumplido"
        case .today: return "Hoy, en curso"
        case .missed: return "No cumplido"
        case .excused(let m): return "\(m.label): no cuenta como fallo"
        case .future: return "Futuro"
        case .beforeStart: return "Antes de empezar"
        }
    }

    private func description(_ mark: DayMark) -> String {
        switch mark {
        case .normal: return "Se evalúa con lo que registres: comidas, entreno y pasos."
        case .rest: return weekday == DayMark.defaultRestWeekday
            ? "Los viernes son descanso por defecto. No cuenta como fallo ni rompe la racha."
            : "No cuenta como fallo ni rompe la racha."
        case .trained: return "Entrenaste aunque no tocara (p. ej. adelantar la sesión del sábado). Cuenta como cumplido."
        case .sick: return "No cuenta como fallo ni rompe la racha. Puedes marcar varios días seguidos."
        case .work: return "Día de trabajo: no cuenta como fallo ni rompe la racha."
        }
    }

    private func sentenceCase(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}
