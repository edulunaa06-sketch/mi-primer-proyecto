import Charts
import SwiftData
import SwiftUI

/// Progreso: cuerpo (peso de tendencia y gasto real), fuerza (récords, 1RM por ejercicio, series por músculo),
/// carrera y constancia.
struct ProgressScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var profiles: [Profile]
    @State private var section: Area = .body
    @State private var expenditure: AdaptiveExpenditure.Result?
    @State private var intakeDays = 0

    enum Area: String, CaseIterable, Identifiable {
        case body = "Cuerpo", strength = "Fuerza", cardio = "Carrera", habit = "Constancia"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Progreso").font(.display(28))
                        Spacer()
                    }
                    .padding(.top, 8)
                    Picker("Sección", selection: $section) {
                        ForEach(Area.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("progress.section")
                    switch section {
                    case .body:
                        WeightChartCard(weights: weights) { app.showWeight = true }
                        expenditureCard
                    case .strength:
                        RecordsCard(workouts: workouts)
                        ExerciseChartCard(workouts: workouts)
                        MuscleVolumeCard(workouts: workouts)
                    case .cardio:
                        CardioCard(workouts: workouts)
                    case .habit:
                        HeatmapCard(workouts: workouts)
                    }
                }
                .padding(.horizontal, 16)
            }
            .atlasScreen()
            .toolbar(.hidden, for: .navigationBar)
            .task(id: weights.count) {
                let intake = Store.dailyIntake(in: context)
                intakeDays = intake.count
                expenditure = AdaptiveExpenditure.estimate(intake: intake, weights: weights.map { .init(date: $0.date, kg: $0.kg) })
            }
        }
    }

    private var expenditureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Tu gasto real")
            if let e = expenditure, let p = profiles.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(NumberFormat.integer(e.kcal)).font(.number(34, .heavy))
                    Text("kcal/día").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.text2)
                }
                Text("Comes de media \(NumberFormat.integer(e.averageIntake)) kcal y tu peso de tendencia ha cambiado \(NumberFormat.signedKg(e.trendChangeKg)) en \(e.daysUsed) días apuntados. Eso es lo que gastas de verdad, no una fórmula.")
                    .font(.footnote).foregroundStyle(DS.text2).fixedSize(horizontal: false, vertical: true)
                let suggested = ((e.kcal * (1 + p.goal.calorieAdjustment)) / 10).rounded() * 10
                if abs(suggested - p.kcalTarget) >= 50 {
                    Button {
                        p.kcalTarget = suggested
                        let m = EnergyCalculator.macros(forKcal: suggested, weightKg: weights.last?.kg, goal: p.goal)
                        p.proteinTarget = m.protein; p.carbsTarget = m.carbs; p.fatTarget = m.fat
                        p.manualTargets = true
                        try? context.save()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: { Label("Ajustar mi objetivo a \(NumberFormat.integer(suggested)) kcal", systemImage: "wand.and.stars") }
                    .buttonStyle(.primary)
                } else {
                    Label("Tu objetivo ya encaja con tu gasto real.", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(DS.good)
                }
            } else {
                Text("ATLAS calcula lo que gastas DE VERDAD con lo que comes y cómo cambia tu peso. Necesita \(AdaptiveExpenditure.minimumDays) días con comidas apuntadas y varios pesajes en las últimas 4 semanas.")
                    .font(.footnote).foregroundStyle(DS.text2).fixedSize(horizontal: false, vertical: true)
                ProgressBarView(fraction: Double(intakeDays) / Double(AdaptiveExpenditure.minimumDays), color: DS.cyan)
                Text("\(min(intakeDays, AdaptiveExpenditure.minimumDays)) de \(AdaptiveExpenditure.minimumDays) días").font(.caption).foregroundStyle(DS.text3)
            }
        }
        .glass()
        .accessibilityIdentifier("expenditure")
    }
}

struct ProgressBarView: View {
    let fraction: Double
    var color: Color = DS.cyan
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 7)
    }
}

struct WeightChartCard: View {
    let weights: [WeightLog]
    let onLog: () -> Void
    @State private var range = 90

    var body: some View {
        let from = Date().addingTimeInterval(-Double(range) * 86400)
        let points = weights.map { WeightTrend.Point(date: $0.date, kg: $0.kg) }
        let trend = WeightTrend.smoothed(points).filter { $0.date >= from }
        let visible = points.filter { $0.date >= from }
        let rate = WeightTrend.weeklyRate(points)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Peso")
                Spacer()
                Button(action: onLog) { Label("Apuntar", systemImage: "plus") }.buttonStyle(.primaryCompact)
                    .accessibilityIdentifier("weight.add")
            }
            HStack(spacing: 18) {
                metric("Tendencia", trend.last.map { NumberFormat.kg($0.kg) + " kg" } ?? "—")
                metric("Ritmo", rate.map { (($0 >= 0) ? "+" : "−") + NumberFormat.kg(abs($0), decimals: 2) + " kg/sem" } ?? "—")
                metric("Último", weights.last.map { NumberFormat.kg($0.kg) + " kg" } ?? "—")
            }
            if visible.count >= 2 {
                Chart {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("Fecha", p.date), y: .value("kg", p.kg))
                            .foregroundStyle(DS.text3).symbolSize(18)
                    }
                    ForEach(Array(trend.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Fecha", p.date), y: .value("Tendencia", p.kg))
                            .foregroundStyle(DS.brand)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(DS.stroke); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(DS.stroke); AxisValueLabel() } }
                .frame(height: 190)
                Picker("Rango", selection: $range) {
                    Text("1 mes").tag(30); Text("3 meses").tag(90); Text("1 año").tag(365)
                }
                .pickerStyle(.segmented)
            } else {
                EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Pésate unos días",
                          message: "Pésate por la mañana, en ayunas. La línea de tendencia quita los vaivenes del agua y te dice si de verdad avanzas.")
            }
        }
        .glass()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(DS.text3)
            Text(value).font(.number(15)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Mejores marcas por ejercicio (1RM estimado), en dorado.
struct RecordsCard: View {
    let workouts: [Workout]

    var body: some View {
        var best: [String: (name: String, e1rm: Double, set: SetSample, date: Date)] = [:]
        for w in workouts {
            for s in w.doneSets {
                guard let sample = s.sample else { continue }
                let e = PersonalRecords.e1rm(sample)
                if e > (best[s.exerciseKey]?.e1rm ?? 0) { best[s.exerciseKey] = (s.exerciseName, e, sample, w.startedAt) }
            }
        }
        let top = best.values.sorted { $0.e1rm > $1.e1rm }.prefix(8)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill").foregroundStyle(DS.goldGradient)
                SectionTitle(title: "Tus récords")
            }
            if top.isEmpty {
                Text("Termina entrenos apuntando kilos y repeticiones: cada vez que superes tu mejor marca, aquí quedará en dorado.")
                    .font(.footnote).foregroundStyle(DS.text2)
            }
            ForEach(Array(top.enumerated()), id: \.offset) { _, r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(NumberFormat.kg(r.set.kg)) kg × \(r.set.reps) · \(DateUtils.dayMonth(r.date))")
                            .font(.system(size: 11)).foregroundStyle(DS.text3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(NumberFormat.integer(r.e1rm)).font(.number(18, .heavy)).foregroundStyle(DS.goldGradient)
                        Text("1RM est.").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.text3)
                    }
                }
            }
        }
        .glass()
        .accessibilityIdentifier("records")
    }
}

/// Evolución del 1RM estimado de un ejercicio.
struct ExerciseChartCard: View {
    let workouts: [Workout]
    @State private var selected: String?

    var body: some View {
        var names: [String: String] = [:]
        var series: [String: [(date: Date, e1rm: Double)]] = [:]
        for w in workouts {
            var bestInWorkout: [String: Double] = [:]
            for s in w.doneSets {
                guard let sample = s.sample else { continue }
                names[s.exerciseKey] = s.exerciseName
                bestInWorkout[s.exerciseKey] = max(bestInWorkout[s.exerciseKey] ?? 0, PersonalRecords.e1rm(sample))
            }
            for (k, v) in bestInWorkout { series[k, default: []].append((w.startedAt, v)) }
        }
        let keys = series.keys.sorted { (series[$0]?.count ?? 0) > (series[$1]?.count ?? 0) }
        let key = selected ?? keys.first
        let data = key.flatMap { series[$0] } ?? []
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Fuerza por ejercicio")
            if keys.isEmpty {
                Text("Aquí verás cómo sube tu fuerza en cada ejercicio.").font(.footnote).foregroundStyle(DS.text2)
            } else {
                Menu {
                    ForEach(keys, id: \.self) { k in Button(names[k] ?? k) { selected = k } }
                } label: {
                    HStack {
                        Text(key.flatMap { names[$0] } ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .foregroundStyle(DS.cyan)
                }
                if data.count >= 2 {
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, p in
                            AreaMark(x: .value("Fecha", p.date), y: .value("1RM", p.e1rm))
                                .foregroundStyle(LinearGradient(colors: [DS.indigo.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Fecha", p.date), y: .value("1RM", p.e1rm))
                                .foregroundStyle(DS.brand)
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(DS.stroke); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .frame(height: 170)
                    if let first = data.first, let last = data.last, first.e1rm > 0 {
                        Text("1RM estimado: \(NumberFormat.integer(first.e1rm)) → \(NumberFormat.integer(last.e1rm)) kg (\(last.e1rm >= first.e1rm ? "+" : "")\(Int(((last.e1rm / first.e1rm) - 1) * 100)) %)")
                            .font(.footnote.weight(.semibold)).foregroundStyle(DS.text2)
                    }
                } else {
                    Text("Haz este ejercicio en dos entrenos para ver la gráfica.").font(.footnote).foregroundStyle(DS.text2)
                }
            }
        }
        .glass()
    }
}

/// Series por músculo esta semana con la franja recomendada (10–20).
struct MuscleVolumeCard: View {
    let workouts: [Workout]

    var body: some View {
        let start = DateUtils.startOfWeek(Date())
        let week = workouts.filter { $0.startedAt >= start }
        let grouped = week.flatMap(\.exerciseGroups).map { (name: $0.name, sets: $0.sets.filter(\.done).count) }
        let volume = WeeklyVolume.sets(grouped)
        let range = WeeklyVolume.target
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Series por músculo · semana")
            Text("Para ganar músculo: \(range.lowerBound)–\(range.upperBound) series por músculo y semana.").font(.footnote).foregroundStyle(DS.text2)
            if volume.isEmpty {
                Text("Aún no hay series esta semana.").font(.footnote).foregroundStyle(DS.text3)
            }
            ForEach(Muscle.allCases.filter { volume[$0] != nil }, id: \.self) { m in
                let v = volume[m] ?? 0
                let ok = Double(range.lowerBound) <= v
                HStack(spacing: 10) {
                    Text(m.rawValue).font(.system(size: 12, weight: .semibold)).frame(width: 112, alignment: .leading)
                    ProgressBarView(fraction: v / Double(range.upperBound), color: ok ? DS.good : DS.indigo)
                    Text(NumberFormat.oneDecimal(v)).font(.number(13)).frame(width: 34, alignment: .trailing)
                }
            }
        }
        .glass()
        .accessibilityIdentifier("muscle.volume")
    }
}

struct CardioCard: View {
    let workouts: [Workout]

    var body: some View {
        let runs = workouts.filter { $0.runMeters > 0 }
        let samples = runs.map { RunSample(date: $0.startedAt, meters: $0.runMeters, seconds: $0.runSeconds) }
        let month = runs.filter { $0.startedAt >= Date().addingTimeInterval(-30 * 86400) }
        let km = month.reduce(0) { $0 + $1.runMeters } / 1000
        let reference = RacePredictor.reference(samples)
        let bestPace = samples.filter { $0.meters >= 1000 }.compactMap { RunMath.paceSecondsPerKm(distanceMeters: $0.meters, seconds: $0.seconds) }.min()
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Km en 30 días", value: NumberFormat.oneDecimal(km), unit: "km", symbol: "map.fill", tint: DS.good)
                StatTile(title: "Mejor ritmo", value: RunMath.formatPace(bestPace).replacingOccurrences(of: " /km", with: ""), unit: "/km", symbol: "bolt.fill", tint: DS.cyan)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Tus tiempos estimados")
                if let reference {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(RacePredictor.distances, id: \.meters) { d in
                            let t = RacePredictor.predict(fromMeters: reference.meters, seconds: reference.seconds, toMeters: d.meters) ?? 0
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text2)
                                Text(RunMath.formatDuration(t)).font(.number(18))
                                Text(RunMath.formatPace(Double(t) / (d.meters / 1000))).font(.system(size: 10).monospacedDigit()).foregroundStyle(DS.text3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surfaceHi))
                        }
                    }
                    Text("Según tu carrera de \(NumberFormat.oneDecimal(reference.meters / 1000)) km en \(RunMath.formatDuration(reference.seconds)) (fórmula de Riegel).")
                        .font(.caption2).foregroundStyle(DS.text3)
                } else {
                    Text("Registra una carrera de 3 km o más y verás tus tiempos estimados en 5 km, 10 km, media y maratón.")
                        .font(.footnote).foregroundStyle(DS.text2)
                }
            }
            .glass()
        }
        .accessibilityIdentifier("cardio")
    }
}

/// Mapa de calor de las últimas 16 semanas: cada cuadro es un día; más intenso cuanto más entrenaste.
struct HeatmapCard: View {
    let workouts: [Workout]

    var body: some View {
        let weeks = 16
        let start = DateUtils.calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: DateUtils.startOfWeek(Date())) ?? Date()
        var perDay: [String: Int] = [:]
        for w in workouts where w.startedAt >= start { perDay[DateUtils.dayKey(w.startedAt), default: 0] += 1 }
        let total = perDay.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Constancia · 16 semanas")
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<weeks, id: \.self) { col in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { row in
                            let d = DateUtils.calendar.date(byAdding: .day, value: col * 7 + row, to: start) ?? start
                            let n = perDay[DateUtils.dayKey(d)] ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(n == 0 ? AnyShapeStyle(DS.surfaceHi) : AnyShapeStyle(DS.brandDiagonal.opacity(n >= 2 ? 1 : 0.65)))
                                .frame(height: 14)
                                .opacity(d > Date() ? 0.25 : 1)
                        }
                    }
                }
            }
            Text("\(total) entrenos en 16 semanas · \(String(format: "%.1f", Double(total) / Double(weeks)).replacingOccurrences(of: ".", with: ",")) por semana")
                .font(.footnote.weight(.semibold)).foregroundStyle(DS.text2)
        }
        .glass()
        .accessibilityIdentifier("heatmap")
    }
}

/// Apuntar el peso de hoy.
struct WeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double?

    var body: some View {
        VStack(spacing: 18) {
            Text("Peso de hoy").font(.display(20))
            HStack(spacing: 14) {
                step(-0.1)
                NumberField(placeholder: "kg", value: $kg, width: 130)
                    .accessibilityIdentifier("weight.field")
                step(+0.1)
            }
            Text("Mejor por la mañana, en ayunas y después del baño.").font(.footnote).foregroundStyle(DS.text2)
            Button {
                if let kg { Store.logWeight(kg, in: context) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } label: { Label("Guardar", systemImage: "checkmark") }
            .buttonStyle(.primary)
            .disabled((kg ?? 0) < 30 || (kg ?? 0) > 300)
            .accessibilityIdentifier("weight.save")
        }
        .padding(24)
        .presentationBackground(Color(red: 0.06, green: 0.065, blue: 0.09))
        .onAppear { kg = Store.latestWeight(context)?.kg }
    }

    private func step(_ delta: Double) -> some View {
        Button {
            kg = (((kg ?? 70) + delta) * 10).rounded() / 10
            DS.haptic(.soft)
        } label: {
            Image(systemName: delta < 0 ? "minus" : "plus").font(.system(size: 16, weight: .heavy))
                .frame(width: 46, height: 46).background(Circle().fill(DS.surfaceHi))
        }
        .buttonStyle(.plain)
    }
}
