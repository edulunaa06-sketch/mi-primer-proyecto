import Charts
import SwiftData
import SwiftUI

struct ProgressHubView: View {
    enum ProgressSection: String, CaseIterable, Identifiable {
        case weight = "Peso", week = "Semana", medals = "Medallas", photos = "Fotos"
        var id: String { rawValue }
    }

    @State private var section: ProgressSection = .weight

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sección", selection: $section) {
                    ForEach(ProgressSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch section {
                case .weight: WeightProgressView()
                case .week: WeeklySummaryView()
                case .medals: MedalsView()
                case .photos: PhotosProgressView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Progreso")
            #if DEBUG
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-NNProgress"), i + 1 < args.count,
                   let s = ProgressSection.allCases.first(where: { "\($0)" == args[i + 1] }) {
                    section = s
                }
            }
            #endif
        }
    }
}

struct WeightProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @State private var showSheet = false
    @State private var pendingDelete: WeightEntry?
    @State private var range: ChartRange = .threeMonths

    private var points: [WeightStats.Point] { entries.map { .init(date: $0.date, kg: $0.weightKg) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button { showSheet = true } label: { Label("Registrar peso", systemImage: "plus") }
                    .buttonStyle(LimeButtonStyle())

                if entries.isEmpty {
                    EmptyStateView(symbol: "scalemass", title: "Sin pesajes", message: "Registra tu primer peso para ver la evolución. Si configuraste un peso inicial en el onboarding aparecerá aquí.")
                        .card()
                } else {
                    chart
                    monthlyCard
                    stats
                    waistCard
                    history
                }
                InfoBanner(text: "El peso fluctúa a diario por agua, glucógeno, sal y digestión. Una variación de un día no confirma pérdida ni ganancia de grasa: fíjate en la tendencia de varias semanas.")
            }
            .padding(16)
        }
        .screenBackground()
        .sheet(isPresented: $showSheet) { WeightEntrySheet() }
        .confirmationDialog("¿Eliminar este pesaje?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let e = pendingDelete { context.delete(e); try? context.save() }
                pendingDelete = nil
            }
        }
    }

    private var stats: some View {
        let first = WeightStats.first(points)
        let latest = WeightStats.latest(points)
        let weekly = WeightStats.change(points: points, days: 7)
        let monthly = WeightStats.change(points: points, days: 30)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Primer registro", value: first.map { NumberFormat.kg($0.kg) + " kg" } ?? "—",
                       detail: first.map { DateUtils.shortDate($0.date) })
            MetricTile(title: "Más reciente", value: latest.map { NumberFormat.kg($0.kg) + " kg" } ?? "—",
                       detail: latest.map { DateUtils.shortDate($0.date) })
            MetricTile(title: "Diferencia total",
                       value: (first != nil && latest != nil && points.count > 1) ? NumberFormat.signedKg(latest!.kg - first!.kg) : "—",
                       detail: "Respecto al primer peso")
            MetricTile(title: "Variación semanal", value: weekly.map(NumberFormat.signedKg) ?? "—",
                       detail: weekly == nil ? "Necesita un registro de hace ≥ 7 días" : "Último vs. hace ≥ 7 días")
            MetricTile(title: "Variación mensual", value: monthly.map(NumberFormat.signedKg) ?? "—",
                       detail: monthly == nil ? "Necesita un registro de hace ≥ 30 días" : "Último vs. hace ≥ 30 días")
            MetricTile(title: "Vs. registro anterior",
                       value: entries.count > 1 ? NumberFormat.signedKg(entries[0].weightKg - entries[1].weightKg) : "—",
                       detail: entries.count > 1 ? "\(entries.count) registros" : "Necesita 2 registros")
        }
    }

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "1M", threeMonths = "3M", sixMonths = "6M", year = "1A", all = "Todo"
        var id: String { rawValue }
        var months: Int? {
            switch self {
            case .month: return 1
            case .threeMonths: return 3
            case .sixMonths: return 6
            case .year: return 12
            case .all: return nil
            }
        }
    }

    private struct IndexedPoint: Identifiable {
        let id: Int
        let point: WeightStats.Point
    }

    /// Evolución: peso de cada día (puntos), tendencia de 7 días (línea gruesa) y media de cada mes (discontinua).
    private var chart: some View {
        let sorted = points.sorted { $0.date < $1.date }
        let cutoff = range.months.flatMap { DateUtils.calendar.date(byAdding: .month, value: -$0, to: Date()) } ?? .distantPast
        let shown = sorted.filter { $0.date >= cutoff }
        let trend = WeightStats.movingAverage(sorted).filter { $0.date >= cutoff }
        let firstShown = sorted.first { $0.date >= cutoff }?.date ?? Date()
        let chartEnd = max(sorted.last?.date ?? Date(), Date())
        // Solo los meses que tienen tramo visible (si no, la línea empezaría después de acabar).
        let monthly = WeightStats.monthlyAverages(sorted).filter { $0.end >= firstShown && $0.start <= chartEnd }
        let values = shown.map(\.kg) + monthly.map(\.averageKg)
        let minKg = ((values.min() ?? 0) - 0.8).rounded(.down)
        let maxKg = ((values.max() ?? 0) + 0.8).rounded(.up)
        let change: Double? = {
            guard let first = trend.first, let last = trend.last, trend.count > 1 else { return nil }
            return last.kg - first.kg
        }()
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Evolución del peso")
            Picker("Periodo", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if let change, let first = trend.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(NumberFormat.signedKg(change))
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(change < 0 ? Theme.lime : Theme.textPrimary)
                    Text("tendencia desde el \(DateUtils.dayMonth(first.date))")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            if shown.isEmpty {
                Text("No hay pesajes en este periodo.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(shown.enumerated().map { IndexedPoint(id: $0.offset, point: $0.element) }) { item in
                        PointMark(x: .value("Fecha", item.point.date), y: .value("Kg", item.point.kg))
                            .foregroundStyle(by: .value("Serie", "Peso diario"))
                            .symbolSize(22)
                    }
                    ForEach(trend.enumerated().map { IndexedPoint(id: 1_000_000 + $0.offset, point: $0.element) }) { item in
                        LineMark(x: .value("Fecha", item.point.date), y: .value("Kg", item.point.kg),
                                 series: .value("Línea", "Tendencia"))
                            .foregroundStyle(by: .value("Serie", "Tendencia 7 días"))
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(monthly) { m in
                        RuleMark(xStart: .value("Inicio", max(m.start, firstShown)),
                                 xEnd: .value("Fin", min(m.end, chartEnd)),
                                 y: .value("Media", m.averageKg))
                            .foregroundStyle(by: .value("Serie", "Media del mes"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                .chartForegroundStyleScale([
                    "Peso diario": Theme.textSecondary,
                    "Tendencia 7 días": Theme.lime,
                    "Media del mes": Theme.textPrimary,
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYScale(domain: minKg...maxKg)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 240)
            }
            Text("Puntos: cada pesaje. Línea verde: media de los últimos 7 días (quita el ruido del agua). Discontinua: media de cada mes.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    /// Media de cada mes, con la diferencia respecto al mes anterior.
    @ViewBuilder
    private var monthlyCard: some View {
        let months = WeightStats.monthlyAverages(points)
        if !months.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Media mensual")
                ForEach(Array(months.enumerated().reversed()), id: \.element.id) { index, m in
                    let previous = index > 0 ? months[index - 1] : nil
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(DateUtils.monthTitle(year: m.year, month: m.month)).font(.subheadline)
                            Text("\(m.count) \(m.count == 1 ? "pesaje" : "pesajes")").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(NumberFormat.kg(m.averageKg)) kg").font(.headline.monospacedDigit())
                            Text(previous.map { NumberFormat.signedKg(m.averageKg - $0.averageKg) + " vs mes anterior" } ?? "Primer mes")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(previous.map { m.averageKg < $0.averageKg ? Theme.lime : Theme.textSecondary } ?? Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider().overlay(Theme.separator)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var waistCard: some View {
        let waists = entries.compactMap { e in e.waistCm.map { (date: e.date, cm: $0) } }.sorted { $0.date < $1.date }
        if let first = waists.first, let last = waists.last {
            HStack {
                MetricTile(title: "Cintura actual", value: NumberFormat.oneDecimal(last.cm) + " cm", detail: DateUtils.shortDate(last.date))
                MetricTile(title: "Cambio de cintura",
                           value: waists.count > 1 ? (last.cm - first.cm >= 0 ? "+" : "−") + NumberFormat.oneDecimal(abs(last.cm - first.cm)) + " cm" : "—",
                           detail: "Desde \(DateUtils.shortDate(first.date))")
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Historial", subtitle: "Mantén pulsado un registro para eliminarlo")
            // `entries` va del más reciente al más antiguo: el anterior de cada registro es el siguiente.
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let previous = index + 1 < entries.count ? entries[index + 1] : nil
                HStack {
                    VStack(alignment: .leading) {
                        Text(DateUtils.shortDate(entry.date)).font(.subheadline)
                        Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if let w = entry.waistCm {
                        Text("\(NumberFormat.oneDecimal(w)) cm").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(NumberFormat.kg(entry.weightKg)) kg").font(.headline.monospacedDigit())
                        Text(previous.map { NumberFormat.signedKg(entry.weightKg - $0.weightKg) + " vs anterior" } ?? "Primer registro")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Eliminar", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                }
                Divider().overlay(Theme.separator)
            }
        }
        .card()
    }
}
