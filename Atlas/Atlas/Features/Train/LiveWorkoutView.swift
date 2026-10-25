import SwiftData
import SwiftUI
import UIKit

/// Entreno en vivo, a pantalla completa. Cada serie muestra lo que hiciste la última vez; el coach te dice
/// qué peso tocar hoy y, si marcas un récord, lo celebras al momento. Sin cuenta atrás: descansas lo que
/// te pida el cuerpo.
struct LiveWorkoutView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var history: [String: [SetSample]] = [:]
    @State private var bests: [String: Double] = [:]
    @State private var addingExercise = false
    @State private var plates: PlatesRequest?
    @State private var confirmDiscard = false
    @State private var summary: Workout?
    @State private var recordFlash: String?

    struct PlatesRequest: Identifiable {
        let id = UUID()
        let kg: Double?
    }

    var body: some View {
        if let summary {
            WorkoutSummaryView(workout: summary) { app.liveWorkout = nil }
        } else {
            live
        }
    }

    private var live: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let recordFlash {
                        Label(recordFlash, systemImage: "trophy.fill")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(DS.bg)
                            .padding(.vertical, 10).padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(DS.goldGradient))
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityIdentifier("record.flash")
                    }
                    ForEach(workout.exerciseGroups) { group in
                        ExerciseBlock(group: group, last: history[group.key] ?? [], best: bests[group.key] ?? 0,
                                      onSetDone: { set in setDone(set) },
                                      onAddSet: { Store.addSet(toExercise: group.key, in: workout, context: context); try? context.save() },
                                      onPlates: { kg in plates = PlatesRequest(kg: kg) })
                    }
                    if workout.sets.isEmpty {
                        EmptyHint(symbol: "plus.circle", title: "Entreno libre", message: "Añade los ejercicios que vas a hacer.")
                    }
                    Button { addingExercise = true } label: { Label("Añadir ejercicio", systemImage: "plus") }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("live.addExercise")
                    Button {
                        Store.finish(workout, in: context)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.easeInOut(duration: 0.3)) { summary = workout }
                    } label: { Label("Terminar entreno", systemImage: "flag.checkered") }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("live.finish")
                    Button("Descartar entreno", role: .destructive) { confirmDiscard = true }
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 4)
                }
                .padding(16)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: recordFlash)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AtlasBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Minimizar")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { plates = PlatesRequest(kg: nil) } label: { Image(systemName: "scalemass") }
                        .accessibilityLabel("Calculadora de discos")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { hideKeyboard() } }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker { ex in
                    Store.addExercise(key: ex.id, name: ex.name, sets: ex.defaultSets, repRange: ex.defaultReps, to: workout, in: context)
                    try? context.save()
                    loadHistory()
                }
            }
            .sheet(item: $plates) { PlateCalculatorSheet(target: $0.kg) }
            .confirmationDialog("¿Descartar este entreno?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) {
                    Store.discard(workout, in: context)
                    app.liveWorkout = nil
                }
            } message: { Text("Se borran las series de hoy. Tu historial no cambia.") }
        }
        .onAppear(perform: loadHistory)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EN CURSO").font(.system(size: 11, weight: .heavy).width(.expanded)).tracking(1.5).foregroundStyle(DS.cyan)
            Text(workout.name).font(.display(26)).lineLimit(2)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let seconds = Int(ctx.date.timeIntervalSince(workout.startedAt))
                HStack(spacing: 16) {
                    Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "stopwatch")
                    Label("\(workout.doneSets.count) series", systemImage: "checkmark.circle")
                    Label("\(NumberFormat.integer(workout.volume)) kg", systemImage: "scalemass")
                }
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(DS.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadHistory() {
        for key in Set(workout.sets.map(\.exerciseKey)) where history[key] == nil {
            history[key] = Store.lastPerformance(key, excluding: workout, in: context)
            bests[key] = Store.bestE1RM(key, excluding: workout, in: context)
        }
    }

    private func setDone(_ set: WorkoutSet) {
        try? context.save()
        guard set.done else { set.isRecord = false; return }
        if let s = set.sample, PersonalRecords.isRecord(s, previousBest: bests[set.exerciseKey] ?? 0) {
            set.isRecord = true
            bests[set.exerciseKey] = PersonalRecords.e1rm(s)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            recordFlash = "¡Récord en \(set.exerciseName)!"
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                recordFlash = nil
            }
        } else {
            DS.haptic(.medium)
        }
    }
}

/// Un ejercicio con sus series.
struct ExerciseBlock: View {
    let group: ExerciseGroup
    let last: [SetSample]
    let best: Double
    let onSetDone: (WorkoutSet) -> Void
    let onAddSet: () -> Void
    let onPlates: (Double?) -> Void

    var body: some View {
        let suggestion = OverloadCoach.suggest(repRange: group.repRange, last: last)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    HStack(spacing: 6) {
                        Text("\(group.sets.count) × \(group.repRange)")
                        if let m = Muscle.worked(by: group.name).first { Text("· \(m.rawValue)") }
                        if best > 0 { Text("· 1RM est. \(NumberFormat.integer(best)) kg") }
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text3)
                }
                Spacer()
                Menu {
                    Button { onPlates(suggestion?.kg ?? last.first?.kg) } label: { Label("Discos y calentamiento", systemImage: "scalemass") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(DS.text2)
                }
            }
            if let s = suggestion {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: s.kind == .increase ? "arrow.up.right.circle.fill" : s.kind == .consolidate ? "equal.circle.fill" : "plus.circle.fill")
                        .font(.title3).foregroundStyle(DS.brandDiagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hoy: \(NumberFormat.kg(s.kg)) kg × \(s.repsMin)–\(s.repsMax)").font(.system(size: 14, weight: .heavy).monospacedDigit())
                        Text(s.reason).font(.system(size: 12)).foregroundStyle(DS.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.indigo.opacity(0.14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coach.suggestion")
            }
            HStack {
                Text("SERIE").frame(width: 42, alignment: .leading)
                Text("ANTERIOR").frame(maxWidth: .infinity, alignment: .leading)
                Text("KG").frame(width: 76)
                Text("REPS").frame(width: 62)
                Text("").frame(width: 40)
            }
            .font(.system(size: 10, weight: .heavy).width(.expanded)).foregroundStyle(DS.text3)
            ForEach(group.sets) { set in
                SetRowView(set: set, previous: set.index < last.count ? last[set.index] : nil, suggestion: suggestion, onToggle: { onSetDone(set) })
            }
            Button(action: onAddSet) { Label("Añadir serie", systemImage: "plus") }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.cyan)
        }
        .glass()
    }
}

struct SetRowView: View {
    @Bindable var set: WorkoutSet
    let previous: SetSample?
    let suggestion: OverloadCoach.Suggestion?
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text("\(set.index + 1)").font(.number(15)).frame(width: 42, alignment: .leading)
            Text(previous.map { "\(NumberFormat.kg($0.kg)) × \($0.reps)" } ?? "—")
                .font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(DS.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            NumberField(placeholder: suggestion.map { NumberFormat.kg($0.kg) } ?? previous.map { NumberFormat.kg($0.kg) } ?? "kg",
                        value: $set.kg, width: 76)
            NumberField(placeholder: previous.map { "\($0.reps)" } ?? "\(suggestion?.repsMin ?? 0)",
                        value: Binding(get: { set.reps.map(Double.init) }, set: { set.reps = $0.map { Int($0.rounded()) } }),
                        decimals: false, width: 62)
            Button {
                // Sin datos, al marcar se usan los de la sugerencia o los de la última vez.
                if !set.done {
                    if set.kg == nil { set.kg = suggestion?.kg ?? previous?.kg }
                    if set.reps == nil { set.reps = previous?.reps ?? suggestion?.repsMin }
                }
                set.done.toggle()
                onToggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(set.done ? AnyShapeStyle(DS.brandDiagonal) : AnyShapeStyle(DS.surfaceHi))
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(set.done ? .white : DS.text3)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .accessibilityLabel(set.done ? "Serie \(set.index + 1) hecha" : "Marcar serie \(set.index + 1)")
            .accessibilityIdentifier("set.check")
        }
        .overlay(alignment: .leading) {
            if set.isRecord {
                Image(systemName: "trophy.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.goldGradient)
                    .offset(x: 16, y: -12)
                    .transition(.scale)
            }
        }
        .padding(.vertical, 2)
        .background(set.done ? DS.indigo.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: set.done)
    }
}

/// Elegir un ejercicio: los de tu rutina y la biblioteca.
struct ExercisePicker: View {
    let onPick: (LibraryExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var templateExercises: [TemplateExercise]
    @State private var query = ""

    var body: some View {
        let mine = templateExercises.map { LibraryExercise(id: $0.key, name: $0.name, defaultSets: $0.sets, defaultReps: $0.repRange) }
        let results = ExerciseLibrary.search(query, extra: mine)
        NavigationStack {
            List(results) { ex in
                Button {
                    onPick(ex)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
                            Text("\(ex.defaultSets) × \(ex.defaultReps)\(ex.muscle.map { " · " + $0.rawValue } ?? "")")
                                .font(.system(size: 11)).foregroundStyle(DS.text3)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(DS.brandDiagonal)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AtlasBackground())
            .searchable(text: $query, prompt: "Buscar ejercicio")
            .navigationTitle("Añadir ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}

/// Resumen al terminar: duración, volumen, series y récords.
struct WorkoutSummaryView: View {
    let workout: Workout
    let onDone: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(DS.brandDiagonal).frame(width: 110, height: 110)
                    .shadow(color: DS.indigo.opacity(0.7), radius: 30)
                Image(systemName: workout.recordCount > 0 ? "trophy.fill" : "checkmark")
                    .font(.system(size: 46, weight: .heavy)).foregroundStyle(.white)
            }
            .scaleEffect(appear ? 1 : 0.3)
            .opacity(appear ? 1 : 0)
            Text("¡Entreno hecho!").font(.display(28))
            Text(workout.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Duración", value: WorkoutMath.duration(workout.durationSeconds), symbol: "stopwatch.fill", tint: DS.cyan)
                StatTile(title: "Volumen", value: NumberFormat.integer(workout.volume), unit: "kg", symbol: "scalemass.fill", tint: DS.indigo)
                StatTile(title: "Series", value: "\(workout.doneSets.count)", symbol: "checkmark.circle.fill", tint: DS.good)
                StatTile(title: "Récords", value: "\(workout.recordCount)", symbol: "trophy.fill", tint: DS.gold)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            Spacer()
            Button("Seguir", action: onDone).buttonStyle(.primary)
                .accessibilityIdentifier("summary.done")
        }
        .padding(24)
        .background(AtlasBackground())
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true } }
    }
}
