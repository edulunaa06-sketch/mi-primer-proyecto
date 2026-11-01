import Charts
import SwiftData
import SwiftUI

/// Biblioteca de ejercicios: buscar, filtrar por músculo, patrón o material, y ver la ficha.
/// También sirve de selector cuando se añade o se sustituye un ejercicio de la rutina.
struct ExerciseLibraryView: View {
    /// Si se pasa, la pantalla funciona como selector: al elegir uno se llama a esta función.
    var onPick: ((ExerciseInfo) -> Void)?
    /// Texto que explica para qué se está eligiendo.
    var pickHint: String?

    @Environment(\.dismiss) private var dismiss
    /// No se usa para pintar la lista (los ejercicios tuyos ya están en el catálogo), pero
    /// hace que la pantalla se vuelva a dibujar en cuanto creas o cambias uno.
    @Query private var mine: [CustomExercise]
    @State private var creating = false
    @State private var search = ""
    @State private var muscle: MuscleGroup?
    @State private var pattern: MovementPattern?
    @State private var equipment: Equipment?

    private var results: [ExerciseInfo] {
        ExerciseCatalog.search(search, muscle: muscle, pattern: pattern, equipment: equipment)
    }

    private var grouped: [(group: MuscleGroup, items: [ExerciseInfo])] {
        Dictionary(grouping: results, by: \.primary)
            .map { (group: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.group < $1.group }
    }

    var body: some View {
        List {
            if let pickHint {
                Section {
                    Text(pickHint).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                filters
            }
            .listRowBackground(Theme.card)

            Section {
                if onPick == nil {
                    NavigationLink { MyExercisesView() } label: {
                        Label("Mis ejercicios (\(mine.count))", systemImage: "square.and.pencil")
                    }
                } else {
                    Button { creating = true } label: {
                        Label("Crear un ejercicio mío", systemImage: "plus.circle.fill")
                    }
                }
            } footer: {
                Text("¿No está el tuyo? Créalo con el músculo que trabaja y contará igual que los de aquí.")
            }
            .listRowBackground(Theme.card)

            if results.isEmpty {
                Section {
                    EmptyStateView(symbol: "magnifyingglass", title: "Sin resultados",
                                   message: "Prueba con otro nombre o quita algún filtro.")
                }
                .listRowBackground(Theme.card)
            }

            ForEach(grouped, id: \.group) { section in
                Section(section.group.label) {
                    ForEach(section.items) { info in
                        row(info)
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .screenBackground()
        .searchable(text: $search, prompt: "Buscar ejercicio")
        .navigationTitle(onPick == nil ? "Ejercicios" : "Elegir ejercicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onPick != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
        .sheet(isPresented: $creating) {
            CustomExerciseFormView { created in
                // Recién creado y ya elegido: se añade a la sesión sin tener que buscarlo.
                onPick?(created.info)
                dismiss()
            }
        }
    }

    private func row(_ info: ExerciseInfo) -> some View {
        Group {
            if let onPick {
                Button {
                    onPick(info)
                    dismiss()
                } label: { label(info) }
            } else {
                NavigationLink { ExerciseDetailView(info: info) } label: { label(info) }
            }
        }
    }

    private func label(_ info: ExerciseInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: info.equipment.symbol)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(info.equipment.label) · \(info.pattern.label)")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if info.isCustom {
                Text("Tuyo").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accentDim, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            if info.isUnilateral {
                Text("1 lado").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.cardRaised, in: Capsule())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                filterMenu(title: muscle?.label ?? "Músculo", isOn: muscle != nil) {
                    Button("Todos") { muscle = nil }
                    ForEach(MuscleGroup.allCases) { group in
                        Button(group.label) { muscle = group }
                    }
                }
                filterMenu(title: equipment?.label ?? "Material", isOn: equipment != nil) {
                    Button("Todos") { equipment = nil }
                    ForEach(Equipment.allCases) { item in
                        Button(item.label) { equipment = item }
                    }
                }
            }
            HStack(spacing: 8) {
                filterMenu(title: pattern?.label ?? "Patrón de movimiento", isOn: pattern != nil) {
                    Button("Todos") { pattern = nil }
                    ForEach(MovementPattern.allCases) { item in
                        Button(item.label) { pattern = item }
                    }
                }
                if muscle != nil || pattern != nil || equipment != nil {
                    Button("Quitar filtros") {
                        muscle = nil; pattern = nil; equipment = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                }
            }
            Text("\(results.count) ejercicios")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterMenu<Content: View>(title: String, isOn: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isOn ? Theme.accentDim : Theme.cardRaised, in: Capsule())
            .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
        }
    }
}

// MARK: - Ficha de un ejercicio

struct ExerciseDetailView: View {
    let info: ExerciseInfo

    @Environment(\.modelContext) private var context
    @State private var history: [ExerciseSessionSummary] = []
    @State private var comparing: ExerciseInfo?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                musclesCard
                if !history.isEmpty { historyCard }
                stepsCard(title: "Cómo se hace", symbol: "list.number", items: info.execution)
                stepsCard(title: "Errores frecuentes", symbol: "exclamationmark.triangle", items: info.mistakes, tint: Theme.warning)
                if let safety = info.safety {
                    InfoBanner(text: safety, symbol: "shield.lefthalf.filled", color: Theme.warning)
                }
                traitCard
                alternativesCard
                Text("Son descripciones técnicas de entrenamiento, no consejo médico. Si algo te duele, "
                     + "no lo fuerces y consúltalo con un profesional.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // El historial se busca por nombre además de por identificador, para que también
            // aparezca el de un ejercicio que el usuario creó a mano con este nombre.
            history = StrengthStore.history(exerciseID: canonicalHistoryID, in: context)
        }
        .sheet(item: $comparing) { other in
            NavigationStack { ExerciseComparisonView(from: info, to: other) }
        }
    }

    /// La rutina guarda los ejercicios con el día delante; aquí se busca el que corresponda.
    private var canonicalHistoryID: String {
        // Se prueba con el id tal cual y con los prefijos de día.
        for prefix in ExerciseCatalog.weekdayPrefixes {
            let candidate = prefix + info.id
            if !StrengthStore.history(exerciseID: candidate, in: context).isEmpty { return candidate }
        }
        return info.id
    }

    private var musclesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Qué trabaja")
            HStack(spacing: 8) {
                chip(info.primary.label, color: Theme.accent, filled: true)
                ForEach(info.secondary) { muscle in
                    chip(muscle.label, color: Theme.textSecondary, filled: false)
                }
            }
            Text("El principal va en color; los demás ayudan y cuentan como media serie en el volumen.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
            Divider().overlay(Theme.separator)
            LabeledContent("Patrón", value: info.pattern.label)
            LabeledContent("Material", value: info.equipment.label)
            LabeledContent("Punto de partida", value: "\(info.defaultSets) × \(info.defaultRepRange)")
            if info.isUnilateral {
                Text("Se hace un lado a la vez: la serie cuenta por lado.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.subheadline)
        .card()
    }

    private func chip(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(filled ? color.opacity(0.18) : Theme.cardRaised, in: Capsule())
            .foregroundStyle(filled ? color : Theme.textSecondary)
    }

    private func stepsCard(title: String, symbol: String, items: [String], tint: Color = Theme.accent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol == "list.number" ? "\(index + 1).circle.fill" : symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private var traitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "En qué se diferencia")
            Text(info.trait)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.equipment.trait)
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var alternativesCard: some View {
        let alternatives = ExerciseCatalog.alternatives(to: info)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Variantes y alternativas",
                          subtitle: "Mismo músculo principal. Toca una para ver exactamente qué cambia.")
            if alternatives.isEmpty {
                Text("No hay otra opción en la biblioteca para este músculo con este patrón.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(alternatives) { other in
                Button { comparing = other } label: {
                    HStack(spacing: 10) {
                        Image(systemName: other.equipment.symbol).font(.caption).foregroundStyle(Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text(other.pattern == info.pattern ? "Mismo patrón" : other.pattern.label)
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(Theme.accent)
                    }
                    .padding(10)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tu historial", subtitle: "1RM estimado de tu mejor serie en cada sesión.")
            OneRepMaxChart(history: history)
            let trend = StrengthTrend(summaries: history)
            HStack(spacing: 10) {
                MetricTile(title: "Sesiones", value: NumberFormat.integer(history.count), symbol: "calendar")
                MetricTile(title: "Tendencia", value: trend.verdict.label,
                           detail: trend.changePercent.map { "\(NumberFormat.oneDecimal($0)) %" },
                           symbol: "chart.line.uptrend.xyaxis")
            }
            if let last = history.last, let text = last.topSetText {
                Text("Última sesión: \(text) · \(DateUtils.dayMonth(last.date))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if trend.verdict == .notEnoughData {
                Text("Con menos de \(StrengthTrend.minimumSessions) sesiones no se puede hablar de tendencia.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }
}

/// Gráfica del 1RM estimado a lo largo del tiempo.
struct OneRepMaxChart: View {
    let history: [ExerciseSessionSummary]

    private var points: [(date: Date, value: Double)] {
        history.compactMap { summary in
            guard let value = summary.estimatedOneRepMax else { return nil }
            return (summary.date, value)
        }
    }

    var body: some View {
        if points.count < 2 {
            Text("Hacen falta al menos dos sesiones con kilos y repeticiones para dibujar la gráfica.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Fecha", point.date), y: .value("1RM estimado", point.value))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Fecha", point.date), y: .value("1RM estimado", point.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(28)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
            .clipped()
        }
    }
}

// MARK: - Comparar dos ejercicios

struct ExerciseComparisonView: View {
    let from: ExerciseInfo
    let to: ExerciseInfo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    side(from, title: "Ahora")
                    Image(systemName: "arrow.right").foregroundStyle(Theme.accent)
                    side(to, title: "Alternativa")
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Qué cambia")
                    ForEach(Array(ExerciseCatalog.difference(from: from, to: to).enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.swap").font(.caption).foregroundStyle(Theme.accent)
                            Text(note).font(.footnote).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()

                InfoBanner(text: "Dos ejercicios del mismo músculo nunca son idénticos: cambia el recorrido, la "
                           + "estabilidad y el reparto de la carga. Al cambiar, la carga que podrás mover será otra "
                           + "y la progresión empieza de nuevo en ese ejercicio.",
                           symbol: "info.circle.fill", color: Theme.accent)

                NavigationLink { ExerciseDetailView(info: to) } label: {
                    Label("Ver la ficha de \(to.name)", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(ActionButtonStyle(filled: false))
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Comparar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
        }
    }

    private func side(_ info: ExerciseInfo, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(Theme.textTertiary)
            Text(info.name).font(.subheadline.weight(.bold))
            Text(info.equipment.label).font(.caption).foregroundStyle(Theme.accent)
            Text(info.pattern.label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}
