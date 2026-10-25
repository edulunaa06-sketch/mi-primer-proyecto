import SwiftData
import SwiftUI

/// Suplementos: lo que tomas, la dosis, cuándo, lo que cuesta al mes y qué se sabe de cada uno.
/// El nivel de evidencia va siempre a la vista, también cuando es «insuficiente».
struct SupplementsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SupplementEntry.createdAt) private var supplements: [SupplementEntry]

    @State private var adding = false
    @State private var infoShown: SupplementInfo?

    private var items: [SupplementPlanItem] { supplements.map(\.planItem) }
    private var warnings: [SupplementChecks.Warning] { SupplementChecks.warnings(items) }
    private var cost: (total: Double, itemsWithoutPrice: Int) { SupplementChecks.monthlyCost(items) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if supplements.isEmpty {
                    EmptyStateView(symbol: "pills",
                                   title: "Sin suplementos apuntados",
                                   message: "Añade lo que tomas y verás la dosis, el coste al mes y lo que dice la evidencia de cada uno.")
                        .card()
                } else {
                    costCard
                    mineCard
                    if !warnings.isEmpty { warningsCard }
                }
                addButton
                catalogCard
                disclaimerCard
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle("Suplementos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack { SupplementPickerView() }
        }
        .sheet(item: $infoShown) { info in
            NavigationStack { SupplementInfoView(info: info) }
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            Label("Añadir un suplemento", systemImage: "plus.circle.fill")
        }
        .buttonStyle(LimeButtonStyle(filled: supplements.isEmpty))
    }

    private var costCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Coste al mes")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(NumberFormat.oneDecimal(cost.total))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("€ / mes").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if cost.itemsWithoutPrice > 0 {
                Text("\(cost.itemsWithoutPrice) sin precio apuntado: el total es solo de los que lo tienen.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private var mineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Lo que tomo")
            ForEach(supplements) { supplement in
                SupplementRow(supplement: supplement, onInfo: { infoShown = $0 })
            }
        }
        .card()
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Avisos")
            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(for: warning.kind))
                        .font(.caption)
                        .foregroundStyle(color(for: warning.kind))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.title).font(.caption.weight(.bold))
                        Text(warning.message).font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }

    private func symbol(for kind: SupplementChecks.Warning.Kind) -> String {
        switch kind {
        case .duplicate: return "doc.on.doc"
        case .tooMuch: return "exclamationmark.triangle.fill"
        case .timing: return "clock.badge.exclamationmark"
        case .consult: return "cross.case.fill"
        case .noEvidence: return "questionmark.circle"
        }
    }

    private func color(for kind: SupplementChecks.Warning.Kind) -> Color {
        switch kind {
        case .tooMuch, .consult: return Theme.danger
        case .duplicate, .timing: return Theme.warning
        case .noEvidence: return Theme.textSecondary
        }
    }

    private var catalogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Qué se sabe de cada uno",
                          subtitle: "Ordenados por la fuerza de la evidencia.")
            ForEach(EvidenceLevel.allCases) { level in
                let group = SupplementCatalog.all.filter { $0.evidence == level }
                if !group.isEmpty {
                    Text(level.label.uppercased())
                        .font(.caption2.weight(.heavy)).tracking(1)
                        .foregroundStyle(evidenceColor(level))
                        .padding(.top, 4)
                    ForEach(group) { info in
                        Button { infoShown = info } label: {
                            HStack(spacing: 8) {
                                Text(info.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private var disclaimerCard: some View {
        Text(SupplementCatalog.disclaimer)
            .font(.caption2).foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

func evidenceColor(_ level: EvidenceLevel) -> Color {
    switch level {
    case .strong: return Theme.lime
    case .moderate: return Theme.carbs
    case .limited: return Theme.warning
    case .insufficient: return Theme.textSecondary
    }
}

// MARK: - Fila de un suplemento

struct SupplementRow: View {
    @Bindable var supplement: SupplementEntry
    let onInfo: (SupplementInfo) -> Void

    @Environment(\.modelContext) private var context
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(supplement.name).font(.subheadline.weight(.semibold))
                    Text(supplement.planItem.doseText)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if let info = supplement.planItem.info {
                        Text(info.evidence.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(evidenceColor(info.evidence))
                    }
                }
                Spacer()
                if let monthly = supplement.planItem.monthlyCost {
                    Text("\(NumberFormat.oneDecimal(monthly)) €")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Menu {
                    if let info = supplement.planItem.info {
                        Button { onInfo(info) } label: { Label("Qué se sabe", systemImage: "info.circle") }
                    }
                    Button { editing = true } label: { Label("Editar", systemImage: "pencil") }
                    Button(role: .destructive) {
                        StrengthStore.remove(supplement, in: context)
                    } label: { Label("Quitar", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("Opciones de \(supplement.name)")
            }
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $editing) {
            NavigationStack { SupplementEditView(supplement: supplement) }
        }
    }
}

// MARK: - Elegir del catálogo

struct SupplementPickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: SupplementInfo?

    var body: some View {
        List {
            ForEach(EvidenceLevel.allCases) { level in
                let group = SupplementCatalog.all.filter { $0.evidence == level }
                if !group.isEmpty {
                    Section(level.label) {
                        ForEach(group) { info in
                            Button { chosen = info } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name).foregroundStyle(Theme.textPrimary)
                                    Text(info.typicalDose).font(.caption2).foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Añadir suplemento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
        }
        .sheet(item: $chosen) { info in
            NavigationStack {
                SupplementNewView(info: info) { dismiss() }
            }
        }
    }
}

/// Formulario para añadir uno del catálogo con su dosis.
struct SupplementNewView: View {
    let info: SupplementInfo
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double?
    @State private var unit: DoseUnit = .gram
    @State private var dosesPerDay = 1.0
    @State private var hour = 9
    @State private var price: Double?
    @State private var days: Int?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Por toma")
                    Spacer()
                    DecimalField(placeholder: "0", value: $amount, width: 80)
                    Picker("", selection: $unit) {
                        ForEach(DoseUnit.allCases) { option in Text(option.label).tag(option) }
                    }
                    .labelsHidden()
                }
                Stepper("Tomas al día: \(Int(dosesPerDay))", value: $dosesPerDay, in: 1...6, step: 1)
                Stepper("Hora: \(hour):00", value: $hour, in: 0...23)
            } header: {
                Text("Dosis")
            } footer: {
                Text("Dosis habitual: \(info.typicalDose)\n\nCuándo: \(info.timing)")
            }

            Section {
                HStack {
                    Text("Precio del envase")
                    Spacer()
                    DecimalField(placeholder: "€", value: $price, width: 80)
                }
                HStack {
                    Text("Días que te dura")
                    Spacer()
                    IntField(placeholder: "días", value: $days, width: 80)
                }
            } header: {
                Text("Coste (opcional)")
            } footer: {
                Text("Con estos dos datos se calcula el coste al mes.")
            }
        }
        .screenBackground()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    let entry = SupplementEntry(catalogID: info.id, name: info.name, ingredient: info.ingredient,
                                                amountPerDose: amount ?? 0, unit: unit,
                                                dosesPerDay: dosesPerDay, hours: [hour])
                    entry.packagePrice = price
                    entry.packageDays = days
                    context.insert(entry)
                    try? context.save()
                    dismiss()
                    onSaved()
                }
                .disabled((amount ?? 0) <= 0)
            }
        }
        .onAppear {
            // Unidad razonable según lo que suele venir en la etiqueta.
            unit = info.ingredient == "cafeína" ? .milligram : .gram
        }
    }
}

/// Editar la dosis y el precio de uno que ya tienes.
struct SupplementEditView: View {
    @Bindable var supplement: SupplementEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Dosis") {
                HStack {
                    Text("Por toma")
                    Spacer()
                    DecimalField(placeholder: "0", value: Binding(
                        get: { supplement.amountPerDose },
                        set: { supplement.amountPerDose = $0 ?? 0 }
                    ), width: 80)
                    Picker("", selection: Binding(
                        get: { supplement.unit }, set: { supplement.unit = $0 }
                    )) {
                        ForEach(DoseUnit.allCases) { option in Text(option.label).tag(option) }
                    }
                    .labelsHidden()
                }
                Stepper("Tomas al día: \(Int(supplement.dosesPerDay))",
                        value: $supplement.dosesPerDay, in: 1...6, step: 1)
            }
            Section("Coste") {
                HStack {
                    Text("Precio del envase")
                    Spacer()
                    DecimalField(placeholder: "€", value: $supplement.packagePrice, width: 80)
                }
                HStack {
                    Text("Días que te dura")
                    Spacer()
                    IntField(placeholder: "días", value: $supplement.packageDays, width: 80)
                }
            }
        }
        .screenBackground()
        .navigationTitle(supplement.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Hecho") {
                    try? context.save()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Ficha de un suplemento

struct SupplementInfoView: View {
    let info: SupplementInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.evidence.label)
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(evidenceColor(info.evidence).opacity(0.16), in: Capsule())
                        .foregroundStyle(evidenceColor(info.evidence))
                    LabeledContent("Dosis habitual") { Text(info.typicalDose).multilineTextAlignment(.trailing) }
                    LabeledContent("Cuándo") { Text(info.timing).multilineTextAlignment(.trailing) }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                list("Para qué sirve", info.benefits, symbol: "checkmark.circle.fill", tint: Theme.lime)
                list("Lo que no hace", info.limits, symbol: "minus.circle.fill", tint: Theme.textSecondary)
                if !info.risks.isEmpty {
                    list("A tener en cuenta", info.risks, symbol: "exclamationmark.triangle.fill", tint: Theme.warning)
                }
                if info.consultFirst {
                    InfoBanner(text: "Conviene hablarlo con un profesional antes de tomarlo. " + SupplementCatalog.disclaimer,
                               symbol: "cross.case.fill", color: Theme.danger)
                }
                Text(SupplementCatalog.disclaimer)
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
        }
    }

    private func list(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol).font(.caption).foregroundStyle(tint)
                    Text(text).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}
