import SwiftUI

/// Editar un ejercicio o crear uno nuevo para el día.
struct ExerciseEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Si viene nil, se está creando uno nuevo.
    let exercise: ExercisePlan?
    /// Devuelve el ejercicio creado (nil si solo se ha editado uno existente).
    let onSave: (ExercisePlan?) -> Void

    @State private var name = ""
    @State private var sets = 3
    @State private var repsMin = 8
    @State private var repsMax = 12
    @State private var restSeconds = 90

    private var isNew: Bool { exercise == nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TextFieldRow(title: "Ejercicio", text: $name, placeholder: "Press banca")

                    VStack(alignment: .leading, spacing: 14) {
                        stepperRow(title: "Series", value: $sets, range: 1...8, unit: "")
                        stepperRow(title: "Repeticiones mínimas", value: $repsMin, range: 1...30, unit: "reps")
                        stepperRow(title: "Repeticiones máximas", value: $repsMax, range: 1...40, unit: "reps")
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Descanso entre series")
                        HStack {
                            Text(DateHelper.restText(restSeconds))
                                .font(Theme.number(24))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Stepper("", value: $restSeconds, in: 30...300, step: 15)
                                .labelsHidden()
                                .tint(Theme.accent)
                        }
                        HStack(spacing: 8) {
                            presetButton("60 s", seconds: 60)
                            presetButton("90 s", seconds: 90)
                            presetButton("2 min", seconds: 120)
                            presetButton("3 min", seconds: 180)
                        }
                    }
                    .card()

                    Button(isNew ? "Añadir" : "Guardar", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid)
                        .opacity(isValid ? 1 : 0.45)
                }
                .padding(Theme.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(isNew ? "Nuevo ejercicio" : "Editar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationBackground(Theme.background)
        .onAppear(perform: load)
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(unit.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(unit)")
                .font(Theme.number(18))
                .foregroundStyle(Theme.text)
            Stepper("", value: value, in: range)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }

    private func presetButton(_ title: String, seconds: Int) -> some View {
        Button {
            restSeconds = seconds
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(restSeconds == seconds ? Color.black : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(restSeconds == seconds ? Theme.accent : Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard let exercise else { return }
        name = exercise.name
        sets = exercise.sets
        repsMin = exercise.repsMin
        repsMax = exercise.repsMax
        restSeconds = exercise.restSeconds
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let low = min(repsMin, repsMax)
        let high = max(repsMin, repsMax)

        if let exercise {
            exercise.name = cleanName
            exercise.sets = sets
            exercise.repsMin = low
            exercise.repsMax = high
            exercise.restSeconds = restSeconds
            onSave(nil)
        } else {
            let new = ExercisePlan(name: cleanName,
                                   sets: sets,
                                   repsMin: low,
                                   repsMax: high,
                                   restSeconds: restSeconds,
                                   order: 0)
            onSave(new)
        }
        dismiss()
    }
}

/// Cambiar el nombre, el tipo y la nota de un día de la rutina.
struct DaySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var day: WorkoutDayPlan
    let onSave: () -> Void

    @State private var name = ""
    @State private var note = ""
    @State private var kind: WorkoutKind = .strength

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TextFieldRow(title: "Nombre del día", text: $name, placeholder: "Push")
                    ChipPicker(title: "Tipo de día",
                               options: WorkoutKind.allCases,
                               label: \.label,
                               selection: $kind,
                               vertical: true)
                        .card()
                    TextFieldRow(title: "Nota", text: $note, placeholder: "Carrera suave de 20-30 min al terminar")

                    Button("Guardar") {
                        day.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? day.name : name
                        day.note = note
                        day.kind = kind
                        onSave()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Theme.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(day.weekdayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
        .onAppear {
            name = day.name
            note = day.note
            kind = day.kind
        }
    }
}

#Preview("Nuevo ejercicio") {
    ExerciseEditorSheet(exercise: nil, onSave: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Ajustes del día") {
    DaySettingsSheet(day: SampleData.pushDay, onSave: {})
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
