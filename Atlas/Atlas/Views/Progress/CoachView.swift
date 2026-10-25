import SwiftData
import SwiftUI

/// Preguntar a la IA sobre tus propios datos.
///
/// Lo que hace esta pantalla, y lo que no:
/// · Antes de enviar nada, enseña exactamente qué datos salen del teléfono.
/// · La IA **no puede cambiar nada**: lo que proponga se queda en texto y lo aplicas tú.
/// · Sin clave de la API no hay respuestas. No se simula una IA que no está.
struct CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ClaudeService.self) private var claude

    @State private var range: ReportRange = .month
    @State private var aiContext: AIContext?
    @State private var question = ""
    @State private var answer: ClaudeAPI.CoachAnswer?
    @State private var errorText: String?
    @State private var showingPayload = false

    /// Preguntas de ejemplo: todas se responden con los datos que la app ya tiene.
    private static let examples = [
        "¿Por qué se me ha estancado el press de banca?",
        "¿Me falta volumen en alguna parte esta semana?",
        "Con mi peso y lo que como, ¿voy hacia donde quiero?",
        "¿Me conviene una semana de descarga?",
        "¿Qué cambiarías de mi rutina esta semana?",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !claude.isConfigured {
                    noKeyCard
                } else {
                    periodPicker
                    if let aiContext {
                        if aiContext.isTooEmptyToBeUseful { tooEmptyCard }
                        dataCard(aiContext)
                    }
                    askCard
                    if let errorText { InfoBanner(text: errorText, symbol: "exclamationmark.triangle.fill", color: Theme.danger) }
                    if claude.isWorking { working }
                    if let answer { answerCard(answer) }
                }
                privacyCard
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle("Preguntar a la IA")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: rebuild)
        .onChange(of: range) { _, _ in rebuild() }
        .sheet(isPresented: $showingPayload) {
            NavigationStack { PayloadView(text: aiContext?.compactText ?? "") }
        }
    }

    private func rebuild() {
        aiContext = StrengthStore.aiContext(range: range, in: modelContext)
    }

    // MARK: Sin clave

    private var noKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "La IA está apagada")
            Text("Esta parte necesita tu propia clave de la API de Claude. Sin ella no hay respuestas: "
                 + "la app no se inventa una IA que no está.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Se activa en Ajustes, y la clave se guarda solo en el Llavero de tu iPhone.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Todo lo demás de ATLAS funciona igual sin clave: entrenamientos, nutrición, volumen, "
                 + "progresión, informes y copia de seguridad.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Datos

    private var periodPicker: some View {
        Picker("Periodo", selection: $range) {
            ForEach(ReportRange.allCases) { option in Text(option.label).tag(option) }
        }
        .pickerStyle(.segmented)
    }

    private var tooEmptyCard: some View {
        InfoBanner(text: "Hay muy poco apuntado en este periodo. Puedes preguntar igual, pero la respuesta "
                   + "valdrá lo que valgan los datos: con dos sesiones no se puede decir gran cosa.",
                   symbol: "tray", color: Theme.warning)
    }

    private func dataCard(_ context: AIContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Qué se envía",
                          subtitle: "Medias y totales de los últimos \(context.periodDays) días. Nada más.")
            ForEach(AIDataScope.allCases) { scope in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Theme.lime)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scope.label).font(.caption.weight(.semibold))
                        Text(scope.detail).font(.caption2).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button {
                showingPayload = true
            } label: {
                Label("Ver el texto exacto que se envía", systemImage: "doc.plaintext")
            }
            .buttonStyle(.secondaryCompact)
        }
        .card()
    }

    // MARK: Preguntar

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tu pregunta")
            TextField("Escribe tu pregunta…", text: $question, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...5)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                ask()
            } label: {
                Label("Preguntar", systemImage: "sparkles")
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || claude.isWorking)

            Text("Ejemplos").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    question = example
                } label: {
                    Text(example)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7).padding(.horizontal, 10)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var working: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Pensando con tus datos…").font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func ask() {
        guard let aiContext else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        answer = nil
        hideKeyboard()
        Task {
            do {
                answer = try await claude.ask(question: text, context: aiContext.compactText)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: Respuesta

    private func answerCard(_ answer: ClaudeAPI.CoachAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Respuesta")
                Text(answer.answer)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !answer.dataUsed.isEmpty {
                block(title: "En qué datos se apoya", items: answer.dataUsed,
                      symbol: "number.circle.fill", tint: Theme.lime)
            }
            if !answer.assumptions.isEmpty {
                block(title: "Lo que ha supuesto", items: answer.assumptions,
                      symbol: "questionmark.circle.fill", tint: Theme.warning)
            }
            if let proposal = answer.proposal, !proposal.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Propuesta")
                    Text(proposal).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Text("La app no cambia nada por su cuenta. Si te convence, aplícalo tú en la rutina "
                         + "o en tus objetivos.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.limeDim, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !answer.missingData.isEmpty {
                block(title: "Para responder mejor, apunta", items: answer.missingData,
                      symbol: "square.and.pencil", tint: Theme.textSecondary)
            }

            Text("Respuesta generada por un modelo de lenguaje a partir de los datos de arriba. "
                 + "Puede equivocarse: no es consejo médico.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func block(title: String, items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(tint)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol).font(.caption2).foregroundStyle(tint)
                    Text(item).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Privacidad

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lo que nunca sale del teléfono")
            ForEach(AIDataExclusions.all, id: \.self) { item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(item).font(.caption2).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}

/// El texto exacto que se enviaría, tal cual, para poder leerlo antes.
struct PayloadView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Sin datos todavía." : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .screenBackground()
        .navigationTitle("Lo que se envía")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
        }
    }
}
