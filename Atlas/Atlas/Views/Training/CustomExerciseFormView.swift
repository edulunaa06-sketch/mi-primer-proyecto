import SwiftData
import SwiftUI

/// Crear o cambiar un ejercicio tuyo: el nombre que le pones y, sobre todo, QUÉ MÚSCULO TRABAJA.
/// Ese es el motivo de esta pantalla: si no se le dice el músculo, las series que apuntas no
/// pueden contar en el volumen de ese músculo ni en el mapa del cuerpo.
struct CustomExerciseFormView: View {
    /// nil = crear uno nuevo.
    var editing: CustomExercise?
    /// Se llama con el ejercicio ya guardado (p. ej. para meterlo en la rutina).
    var onSaved: ((CustomExercise) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.name) private var mine: [CustomExercise]

    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []
    @State private var pattern: MovementPattern = .horizontalPush
    @State private var patternTouched = false
    @State private var equipment: Equipment = .machine
    @State private var unilateral = false
    @State private var sets = 3
    @State private var repMin = 8
    @State private var repMax = 12
    @State private var note = ""
    @State private var loaded = false

    private var problem: CustomExerciseRules.Problem? {
        CustomExerciseRules.validate(name: name, mine: mine.map { (id: $0.id, name: $0.name) },
                                     editingID: editing?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (p. ej. jalón al pecho enfatizando espalda alta)", text: $name, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("custom.exercise.name")
                    if let problem, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(problem.message).font(.caption).foregroundStyle(Theme.danger)
                    }
                } header: {
                    Text("Cómo lo llamas")
                } footer: {
                    Text("Ponle el nombre con el que lo apuntas. Si ya tenías series apuntadas con ese mismo "
                         + "nombre, empezarán a contar en el músculo que elijas aquí abajo.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("Músculo principal", selection: $primary) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.label).tag(group)
                        }
                    }
                    .onChange(of: primary) { _, new in
                        secondary.remove(new)
                        // Mientras no lo toques tú, el patrón sigue al músculo.
                        if !patternTouched { pattern = CustomExerciseRules.suggestedPattern(for: new) }
                    }
                } header: {
                    Text("Qué músculo trabaja")
                } footer: {
                    Text("Cada serie que apuntes cuenta entera para este músculo. Es lo que se usa en el "
                         + "volumen semanal, en el mapa del cuerpo y en los informes.")
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(MuscleGroup.allCases.filter { $0 != primary }) { group in
                        Button {
                            if secondary.contains(group) { secondary.remove(group) } else { secondary.insert(group) }
                        } label: {
                            HStack {
                                Text(group.label).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if secondary.contains(group) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.lime)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Músculos que ayudan (opcional)")
                } footer: {
                    Text("Cada serie cuenta como media serie para estos. Es la forma habitual de contar el "
                         + "trabajo indirecto; es una estimación, no una medida.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("Material", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in Text(item.label).tag(item) }
                    }
                    Picker("Patrón de movimiento", selection: $pattern) {
                        ForEach(MovementPattern.allCases) { item in Text(item.label).tag(item) }
                    }
                    .onChange(of: pattern) { _, _ in patternTouched = true }
                    Toggle("Un lado cada vez", isOn: $unilateral)
                    Stepper("Series: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps mínimas: \(repMin)", value: $repMin, in: 1...100)
                        .onChange(of: repMin) { _, v in if repMax < v { repMax = v } }
                    Stepper("Reps máximas: \(repMax)", value: $repMax, in: 1...100)
                        .onChange(of: repMax) { _, v in if repMin > v { repMin = v } }
                } header: {
                    Text("Detalles")
                } footer: {
                    Text("El material y el patrón solo se usan para proponerte sustitutos parecidos cuando "
                         + "una máquina está ocupada. Las series y las repeticiones son el punto de partida.")
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("Cómo lo haces tú: ángulo, agarre, máquina…", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Nota (opcional)")
                }
                .listRowBackground(Theme.card)
            }
            .screenBackground()
            .navigationTitle(editing == nil ? "Ejercicio nuevo" : "Editar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(problem != nil)
                        .accessibilityIdentifier("custom.exercise.save")
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                if let editing {
                    name = editing.name
                    primary = editing.primary
                    secondary = Set(editing.secondary)
                    pattern = editing.pattern
                    patternTouched = true
                    equipment = editing.equipment
                    unilateral = editing.isUnilateral
                    sets = editing.defaultSets
                    repMin = editing.defaultRepMin
                    repMax = editing.defaultRepMax
                    note = editing.note
                } else {
                    pattern = CustomExerciseRules.suggestedPattern(for: primary)
                }
            }
        }
    }

    private func save() {
        if let editing {
            StrengthStore.updateCustomExercise(editing, name: name, primary: primary,
                                               secondary: Array(secondary), pattern: pattern,
                                               equipment: equipment, unilateral: unilateral, sets: sets,
                                               repMin: repMin, repMax: repMax, note: note, in: context)
            onSaved?(editing)
        } else if let created = StrengthStore.createCustomExercise(
            name: name, primary: primary, secondary: Array(secondary), pattern: pattern,
            equipment: equipment, unilateral: unilateral, sets: sets, repMin: repMin,
            repMax: repMax, note: note, in: context) {
            onSaved?(created)
        }
        dismiss()
    }
}

/// Lista de los ejercicios que te has creado tú, para cambiarlos o quitarlos.
struct MyExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomExercise.name) private var mine: [CustomExercise]

    @State private var creating = false
    @State private var editing: CustomExercise?
    @State private var deleting: CustomExercise?

    var body: some View {
        List {
            Section {
                Button { creating = true } label: {
                    Label("Crear un ejercicio mío", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("custom.exercise.create")
            } footer: {
                Text("Para lo que no está en la biblioteca. Al decirle qué músculo trabaja, las series que "
                     + "apuntes cuentan en el volumen de ese músculo y en el mapa del cuerpo.")
            }
            .listRowBackground(Theme.card)

            if mine.isEmpty {
                Section {
                    EmptyStateView(symbol: "square.and.pencil", title: "Todavía ninguno",
                                   message: "Cuando te crees uno, aparecerá aquí y también en la biblioteca.")
                }
                .listRowBackground(Theme.card)
            } else {
                Section("Mis ejercicios") {
                    ForEach(mine) { exercise in
                        Button { editing = exercise } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).foregroundStyle(Theme.textPrimary)
                                Text(summary(exercise)).font(.caption).foregroundStyle(Theme.textSecondary)
                                if !exercise.aliases.isEmpty {
                                    Text("Antes: \(exercise.aliases.joined(separator: ", "))")
                                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Eliminar", role: .destructive) { deleting = exercise }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .screenBackground()
        .navigationTitle("Mis ejercicios")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { CustomExerciseFormView() }
        .sheet(item: $editing) { exercise in CustomExerciseFormView(editing: exercise) }
        .confirmationDialog("¿Quitar este ejercicio de los tuyos?", isPresented: .init(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Quitar", role: .destructive) {
                if let deleting { StrengthStore.deleteCustomExercise(deleting, in: context) }
                deleting = nil
            }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: {
            if let deleting {
                let count = StrengthStore.loggedSetCount(forExerciseNamed: deleting.name, in: context)
                Text(count > 0
                     ? "No se borra nada de lo que has entrenado. Lo que pasa es que esas "
                       + NumberFormat.plural(count, "1 serie dejará", "\(count) series dejarán")
                       + " de contar en \(deleting.primary.label.lowercased())."
                     : "No tienes series apuntadas con este nombre.")
            }
        }
    }

    private func summary(_ exercise: CustomExercise) -> String {
        var parts = [exercise.primary.label]
        if !exercise.secondary.isEmpty {
            parts.append("ayudan: " + exercise.secondary.map(\.shortLabel).joined(separator: ", "))
        }
        parts.append(exercise.equipment.label)
        return parts.joined(separator: " · ")
    }
}
