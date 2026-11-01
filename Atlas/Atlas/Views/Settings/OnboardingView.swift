import SwiftData
import SwiftUI

/// Configuración inicial. Los valores de referencia del usuario (85,1 kg · 22/10/2026) se ofrecen
/// como sugerencia, pero SOLO se guardan si el usuario los confirma. Nunca se duplican.
struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var weight: Double?
    @State private var startDate = Date()
    @State private var message: String?

    static let suggestedWeight = 85.1
    static var suggestedDate: Date {
        DateUtils.calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 8)) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOW OR NEVER")
                            .font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Theme.accent)
                        Text("Configura tu punto de partida")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        Text("Introduce tu peso inicial y la fecha en la que empieza el seguimiento. Puedes cambiarlo más tarde en Ajustes.")
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Peso inicial (kg)")
                            Spacer()
                            DecimalField(placeholder: "0,0", value: $weight, width: 110)
                        }
                        DatePicker("Fecha de inicio", selection: $startDate, displayedComponents: .date)
                        Button("Usar 85,1 kg · 22 oct 2026") {
                            weight = Self.suggestedWeight
                            startDate = Self.suggestedDate
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tu semana").font(.headline)
                        Text("Empiezas con la semana en blanco: los siete días en descanso. En Entrenar "
                             + "decides cuáles son de gimnasio, cuáles de carrera o de otro deporte, cómo se "
                             + "llaman y qué ejercicios llevan.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .card()

                    if !weights.isEmpty {
                        InfoBanner(text: "Ya tienes \(weights.count) pesaje(s) guardado(s). Si ya existe un pesaje con el mismo peso en esa fecha no se volverá a crear.", symbol: "checkmark.shield.fill", color: Theme.accent)
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Theme.danger)
                    }

                    Button("Siguiente") { save() }
                        .buttonStyle(ActionButtonStyle())
                        .disabled(weight == nil)
                    Button("Omitir por ahora") { finish(saveStart: false) }
                        .buttonStyle(ActionButtonStyle(filled: false))

                    Text("Los objetivos de nutrición (2.300 kcal, 180 g P, 250 g C, 65 g G) son provisionales y editables en Ajustes.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        guard let weight, (20...400).contains(weight) else {
            message = "Introduce un peso válido entre 20 y 400 kg."
            return
        }
        DataStore.addWeight(weight, waist: nil, date: startDate, in: context)
        finish(saveStart: true)
    }

    private func finish(saveStart: Bool) {
        let settings = settingsList.first ?? DataStore.settings(context)
        if saveStart { settings.trackingStartDate = DateUtils.startOfDay(startDate) }
        // Sin rutina de serie: la semana empieza en blanco y la monta el usuario.
        DataStore.startRoutineFromScratch(in: context)
        settings.onboardingCompleted = true
        try? context.save()
        onFinish()
    }
}
