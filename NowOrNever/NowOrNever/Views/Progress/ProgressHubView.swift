import Charts
import SwiftData
import SwiftUI

struct ProgressHubView: View {
    enum ProgressSection: String, CaseIterable, Identifiable {
        case weight = "Peso", photos = "Fotos"
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
                case .photos: PhotosProgressView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Progreso")
        }
    }
}

struct WeightProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @State private var showSheet = false
    @State private var pendingDelete: WeightEntry?

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
                    stats
                    chart
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
            MetricTile(title: "Registros", value: "\(entries.count)", detail: nil)
        }
    }

    private var chart: some View {
        let sorted = points.sorted { $0.date < $1.date }
        let minKg = (sorted.map(\.kg).min() ?? 0) - 1
        let maxKg = (sorted.map(\.kg).max() ?? 0) + 1
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Evolución")
            Chart(sorted, id: \.date) { p in
                LineMark(x: .value("Fecha", p.date), y: .value("Kg", p.kg))
                    .foregroundStyle(Theme.lime)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Fecha", p.date), y: .value("Kg", p.kg))
                    .foregroundStyle(Theme.lime)
                    .symbolSize(24)
            }
            .chartYScale(domain: minKg...maxKg)
            .frame(height: 200)
        }
        .card()
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
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(DateUtils.shortDate(entry.date)).font(.subheadline)
                        Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if let w = entry.waistCm {
                        Text("\(NumberFormat.oneDecimal(w)) cm").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Text("\(NumberFormat.kg(entry.weightKg)) kg").font(.headline.monospacedDigit())
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Eliminar", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                }
                Divider().overlay(Color.white.opacity(0.06))
            }
        }
        .card()
    }
}
