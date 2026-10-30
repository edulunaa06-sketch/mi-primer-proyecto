import SwiftData
import SwiftUI

/// Montar la semana a tu manera: qué es cada día (fuerza, carrera o descanso), cómo se llama
/// y, si es de fuerza, qué ejercicios lleva.
///
/// La rutina que trae la app de serie es una propuesta, no una imposición: aquí se cambia
/// entera. Lo que NO se toca es el identificador de cada sesión, así que todo lo que ya
/// tengas entrenado sigue en su sitio aunque cambies el día de arriba abajo.
struct WeekPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var titles: [SessionTitle]
    @Query private var kinds: [SessionKindChoice]

    /// Los nombres mientras se escriben. Se guardan al salir, no en cada letra.
    @State private var names: [String: String] = [:]
    @State private var editingExercises: SessionDefinition?

    var body: some View {
        NavigationStack {
            List {
                ForEach(1...7, id: \.self) { weekday in
                    Section {
                        ForEach(WeeklyRoutine.sessions(forWeekday: weekday)) { base in
                            sessionRow(base)
                        }
                    } header: {
                        Text(WeeklyRoutine.weekdayName(weekday))
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Text("Cambiar un día no borra nada: lo que ya entrenaste se queda en el historial. "
                         + "Si pones un día en descanso deja de contar para el cumplimiento semanal.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(AtlasBackground())
            .navigationTitle("Mi semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { saveNames(); dismiss() }
                }
            }
            .onAppear(perform: loadNames)
            .onDisappear(perform: saveNames)
            .sheet(item: $editingExercises) { session in
                RoutineEditorView(session: session)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ base: SessionDefinition) -> some View {
        let resolved = base.resolved(with: [], titles: titles, kinds: kinds)
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nombre del día", text: Binding(
                get: { names[base.id] ?? resolved.title },
                set: { names[base.id] = $0 }
            ))
            .font(.body.weight(.semibold))
            .accessibilityIdentifier("planner.name.\(base.id)")

            Picker("Qué haces este día", selection: Binding(
                get: { resolved.kind },
                set: { DataStore.setKind($0, for: base.id, in: context) }
            )) {
                ForEach(SessionKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("planner.kind.\(base.id)")

            if resolved.kind == .strength {
                Button {
                    // El editor necesita la sesión ya resuelta: si este día era de carrera y lo
                    // acabas de pasar a fuerza, tiene que abrirse como fuerza.
                    editingExercises = resolved
                } label: {
                    Label(exercisesLabel(for: base.id), systemImage: "list.bullet")
                        .font(.footnote.weight(.semibold))
                }
                .accessibilityIdentifier("planner.exercises.\(base.id)")
            }
        }
        .padding(.vertical, 4)
    }

    /// Cuántos ejercicios tiene ya ese día, para no tener que entrar a mirarlo.
    private func exercisesLabel(for sessionID: String) -> String {
        let count = DataStore.routine(for: sessionID, in: context).count
        switch count {
        case 0: return "Poner los ejercicios"
        case 1: return "1 ejercicio · cambiar"
        default: return "\(count) ejercicios · cambiar"
        }
    }

    private func loadNames() {
        guard names.isEmpty else { return }
        for base in WeeklyRoutine.allSessions {
            names[base.id] = base.resolved(with: [], titles: titles, kinds: kinds).title
        }
    }

    /// Se guarda al salir y no en cada letra: así escribir no va dando tirones.
    private func saveNames() {
        for base in WeeklyRoutine.allSessions {
            guard let typed = names[base.id] else { continue }
            let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = base.resolved(with: [], titles: titles, kinds: kinds).title
            guard clean != current else { continue }
            DataStore.renameSession(base.id, to: clean, in: context)
        }
    }
}
