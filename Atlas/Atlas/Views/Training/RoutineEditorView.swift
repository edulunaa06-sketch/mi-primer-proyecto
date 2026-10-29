import Charts
import SwiftData
import SwiftUI

/// Edición de la rutina de una sesión de fuerza: añadir, eliminar, sustituir, reordenar
/// y cambiar series/repeticiones. Los cambios se guardan al momento y no borran el historial.
struct RoutineEditorView: View {
    let session: SessionDefinition

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [RoutineExercise]

    @State private var editing: RoutineExercise?
    @State private var substituting: RoutineExercise?
    @State private var substitutingFromLibrary: RoutineExercise?
    @State private var adding = false
    @State private var addingFromLibrary = false
    @State private var confirmRestore = false
    @State private var editMode: EditMode = .inactive

    init(session: SessionDefinition) {
        self.session = session
        let id = session.id
        _exercises = Query(filter: #Predicate<RoutineExercise> { $0.sessionID == id }, sort: \.order)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if exercises.isEmpty {
                        Text("Sin ejercicios. Añade uno abajo.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(exercises) { ex in
                        Button { editing = ex } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).foregroundStyle(Theme.textPrimary)
                                    Text("\(ex.sets) series · \(ex.repRange) reps")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.lime)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Eliminar", role: .destructive) { DataStore.removeExercise(ex, in: context) }
                            Button("Cambiar") { substitutingFromLibrary = ex }.tint(.orange)
                        }
                    }
                    .onMove { from, to in
                        DataStore.moveExercises(in: session.id, from: from, to: to, in: context)
                    }
                } header: {
                    Text(session.title)
                } footer: {
                    Text("Toca un ejercicio para cambiar series y repeticiones. Desliza a la izquierda para cambiarlo por otro o eliminarlo. Usa “Ordenar” para cambiar el orden. El historial de semanas anteriores no se modifica.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button { addingFromLibrary = true } label: {
                        Label("Añadir de la biblioteca", systemImage: "books.vertical.fill")
                    }
                    Button { adding = true } label: { Label("Crear un ejercicio mío", systemImage: "plus.circle.fill") }
                    Button("Restaurar rutina predeterminada", role: .destructive) { confirmRestore = true }
                } footer: {
                    Text("La biblioteca trae \(ExerciseCatalog.all.count) ejercicios con su músculo principal, el patrón, "
                         + "el material y los errores frecuentes. Si el tuyo no está, créalo: al decirle qué músculo "
                         + "trabaja, las series que apuntes cuentan en el volumen de ese músculo.")
                }
                .listRowBackground(Theme.card)
            }
            .environment(\.editMode, $editMode)
            .screenBackground()
            .navigationTitle("Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Fin de ordenar" : "Ordenar") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
            }
            .sheet(item: $editing) { ex in
                ExerciseFormView(title: "Editar ejercicio", name: ex.name, sets: ex.sets, repMin: ex.repMin, repMax: ex.repMax,
                                 nameEditable: false) { _, sets, lo, hi in
                    ex.sets = sets
                    ex.repMin = lo
                    ex.repMax = hi
                    try? context.save()
                }
            }
            .sheet(item: $substituting) { ex in
                ExerciseFormView(title: "Sustituir \(ex.name)", name: "", sets: ex.sets, repMin: ex.repMin, repMax: ex.repMax,
                                 nameEditable: true,
                                 footer: "El ejercicio nuevo ocupa la misma posición y empieza su propia progresión. El historial del anterior se conserva.") { name, _, _, _ in
                    DataStore.substitute(ex, withName: name, in: context)
                }
            }
            .sheet(item: $substitutingFromLibrary) { ex in
                NavigationStack {
                    ExerciseLibraryView(onPick: { info in
                        StrengthStore.substitute(ex, with: info, in: context)
                    }, pickHint: "Vas a cambiar «\(ex.name)». El nuevo ejercicio ocupa su sitio y se queda con "
                       + "\(ex.sets) series de \(ex.repRange) repeticiones, así que el objetivo de la sesión no cambia. "
                       + "El historial del anterior se conserva y el nuevo empieza su propia progresión.")
                }
            }
            .sheet(isPresented: $addingFromLibrary) {
                NavigationStack {
                    ExerciseLibraryView(onPick: { info in
                        StrengthStore.addExercise(to: session.id, from: info, in: context)
                    }, pickHint: "Se añade al final de la sesión con su punto de partida de series y repeticiones. "
                       + "Puedes cambiarlo después.")
                }
            }
            .sheet(isPresented: $adding) {
                CustomExerciseFormView { created in
                    StrengthStore.addExercise(to: session.id, from: created.info, in: context)
                }
            }
            .confirmationDialog("¿Restaurar la rutina predeterminada de esta sesión?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restaurar", role: .destructive) { DataStore.restoreDefaultRoutine(for: session, in: context) }
            } message: {
                Text("Se perderán tus cambios en esta sesión. Los registros de entrenamientos anteriores se mantienen.")
            }
        }
    }
}

/// Formulario de nombre, series y rango de repeticiones.
struct ExerciseFormView: View {
    let title: String
    @State var name: String
    @State var sets: Int
    @State var repMin: Int
    @State var repMax: Int
    var nameEditable: Bool
    var footer: String?
    var onSave: (String, Int, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    init(title: String, name: String, sets: Int, repMin: Int, repMax: Int, nameEditable: Bool,
         footer: String? = nil, onSave: @escaping (String, Int, Int, Int) -> Void) {
        self.title = title
        _name = State(initialValue: name)
        _sets = State(initialValue: sets)
        _repMin = State(initialValue: repMin)
        _repMax = State(initialValue: repMax)
        self.nameEditable = nameEditable
        self.footer = footer
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if nameEditable {
                        TextField("Nombre del ejercicio", text: $name)
                    } else {
                        Text(name)
                    }
                    Stepper("Series: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps mínimas: \(repMin)", value: $repMin, in: 1...100)
                        .onChange(of: repMin) { _, v in if repMax < v { repMax = v } }
                    Stepper("Reps máximas: \(repMax)", value: $repMax, in: 1...100)
                        .onChange(of: repMax) { _, v in if repMin > v { repMin = v } }
                    LabeledContent("Prescripción", value: "\(sets) × \(ExerciseDefinition.formatRange(min: repMin, max: repMax))")
                } footer: {
                    if let footer { Text(footer) }
                }
            }
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(trimmedName, sets, repMin, repMax)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
