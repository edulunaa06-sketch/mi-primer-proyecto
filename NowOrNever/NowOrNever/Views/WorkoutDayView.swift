import SwiftUI
import SwiftData

/// Un día de entreno: apuntar series, ver lo de la última vez y descansar.
struct WorkoutDayView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: WorkoutDayPlan

    @State private var timer = RestTimer()
    @State private var session: WorkoutSession?
    @State private var history: [String: ExerciseHistory] = [:]
    @State private var exerciseToEdit: ExercisePlan?
    @State private var showingNewExercise = false
    @State private var showingDaySettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: Theme.Spacing.normal) {
                    headerCard

                    if day.kind.hasExercises {
                        if let session {
                            ForEach(day.sortedExercises) { exercise in
                                ExerciseCard(exercise: exercise,
                                             session: session,
                                             history: history[exercise.name],
                                             onRest: { startRest(for: exercise) },
                                             onEdit: { exerciseToEdit = exercise },
                                             onDelete: { delete(exercise) })
                            }
                        }

                        Button {
                            showingNewExercise = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "plus")
                                Text("Añadir ejercicio")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    if day.kind.hasCardio, let session {
                        CardioCard(session: session)
                    }

                    if day.kind == .rest {
                        restCard
                    }
                }
                .padding(Theme.Spacing.screen)
                .padding(.bottom, timer.isActive ? 190 : 30)
            }
            .scrollDismissesKeyboard(.interactively)

            if timer.isActive {
                RestTimerBar(timer: timer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: timer.isActive)
        .screenBackground()
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDaySettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear(perform: load)
        .sheet(item: $exerciseToEdit) { exercise in
            ExerciseEditorSheet(exercise: exercise) { _ in saveAndReload() }
        }
        .sheet(isPresented: $showingNewExercise) {
            ExerciseEditorSheet(exercise: nil) { newExercise in
                if let newExercise {
                    newExercise.order = (day.exercises.map(\.order).max() ?? -1) + 1
                    newExercise.day = day
                    day.exercises.append(newExercise)
                }
                saveAndReload()
            }
        }
        .sheet(isPresented: $showingDaySettings) {
            DaySettingsSheet(day: day, onSave: saveAndReload)
        }
    }

    // MARK: - Piezas

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TagLabel(text: day.weekdayName)
                TagLabel(text: day.kind.label, color: Theme.textSecondary)
            }
            Text(day.name)
                .font(Theme.screenTitle)
                .foregroundStyle(Theme.text)
            if !day.note.isEmpty {
                Text(day.note)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if day.kind.hasExercises {
                Text("Apunta peso y repeticiones de cada serie. Debajo de cada ejercicio tienes lo que hiciste la última vez.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private var restCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Theme.accent)
            Text("Hoy toca descansar")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.text)
            Text("Come bien, duerme y vuelve mañana con todo.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    // MARK: - Datos

    private func load() {
        let current = PlanService.session(for: day, on: .now, context: context)
        session = current
        loadHistory()
    }

    private func saveAndReload() {
        normalizeOrder()
        if let session {
            PlanService.syncSets(of: day, in: session, context: context)
        }
        try? context.save()
        loadHistory()
    }

    private func normalizeOrder() {
        for (index, exercise) in day.sortedExercises.enumerated() {
            exercise.order = index
        }
    }

    /// Busca la última vez que se hizo cada ejercicio.
    private func loadHistory() {
        var result: [String: ExerciseHistory] = [:]
        for exercise in day.exercises {
            guard let last = PlanService.lastSession(for: exercise.name, before: .now, context: context) else { continue }
            let summary = last.logs.map(\.summary).joined(separator: "   ")
            result[exercise.name] = ExerciseHistory(
                date: last.session.date,
                summary: summary,
                suggestIncrease: PlanService.shouldIncreaseWeight(for: exercise, lastLogs: last.logs)
            )
        }
        history = result
    }

    private func startRest(for exercise: ExercisePlan) {
        timer.start(seconds: exercise.restSeconds, exercise: exercise.name)
    }

    private func delete(_ exercise: ExercisePlan) {
        day.exercises.removeAll { $0.id == exercise.id }
        context.delete(exercise)
        saveAndReload()
    }
}

/// Lo que se hizo la última vez con un ejercicio.
struct ExerciseHistory {
    let date: Date
    let summary: String
    let suggestIncrease: Bool
}

// MARK: - Tarjeta de ejercicio

struct ExerciseCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var exercise: ExercisePlan
    let session: WorkoutSession
    let history: ExerciseHistory?
    let onRest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var logs: [SetLog] {
        session.logs(for: exercise.name).prefix(exercise.sets).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 8) {
                        Text(exercise.schemeText)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("Descanso \(exercise.restText)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Editar ejercicio", systemImage: "pencil", action: onEdit)
                    Button("Quitar del día", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 28)
                }
            }

            if history?.suggestIncrease == true {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 13, weight: .black))
                    Text("Sube peso: la última vez completaste todas las series al máximo del rango.")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(spacing: 8) {
                ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                    SetRow(log: log, number: index + 1, onFinish: onRest)
                }
            }

            if let history {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Última vez · \(DateHelper.shortDate(history.date))")
                        .font(Theme.overline)
                        .kerning(1)
                        .foregroundStyle(Theme.textTertiary)
                    Text(history.summary)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            } else {
                Text("Primera vez con este ejercicio.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }
}

/// Una serie: número, peso, repeticiones y botón de descanso.
struct SetRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var log: SetLog
    let number: Int
    let onFinish: () -> Void

    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(log.isFilled ? Color.black : Theme.textSecondary)
                .frame(width: 30, height: 38)
                .background(log.isFilled ? Theme.accent : Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            field(text: $weightText, placeholder: "kg")
            field(text: $repsText, placeholder: "reps")

            Button(action: onFinish) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 38)
                    .background(Theme.accentMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            weightText = log.weightKg > 0 ? Formatters.weight(log.weightKg) : ""
            repsText = log.reps > 0 ? String(log.reps) : ""
        }
        .onChange(of: weightText) {
            log.weightKg = Formatters.parse(weightText) ?? 0
            try? context.save()
        }
        .onChange(of: repsText) {
            log.reps = Int(repsText.trimmingCharacters(in: .whitespaces)) ?? 0
            try? context.save()
        }
    }

    private func field(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Carrera

struct CardioCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession

    @State private var km = ""
    @State private var minutes = ""

    private var pace: String? {
        guard session.distanceKm > 0, session.durationMinutes > 0 else { return nil }
        let paceMinutes = session.durationMinutes / session.distanceKm
        let whole = Int(paceMinutes)
        let seconds = Int((paceMinutes - Double(whole)) * 60)
        return String(format: "%d:%02d min/km", whole, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Carrera")
            HStack(spacing: 12) {
                NumberField(title: "Distancia", text: $km, unit: "km")
                NumberField(title: "Tiempo", text: $minutes, unit: "min")
            }
            if let pace {
                Text("Ritmo: \(pace)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .card()
        .onAppear {
            km = session.distanceKm > 0 ? Formatters.weight(session.distanceKm) : ""
            minutes = session.durationMinutes > 0 ? Formatters.weight(session.durationMinutes) : ""
        }
        .onChange(of: km) {
            session.distanceKm = Formatters.parse(km) ?? 0
            try? context.save()
        }
        .onChange(of: minutes) {
            session.durationMinutes = Formatters.parse(minutes) ?? 0
            try? context.save()
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutDayView(day: SampleData.pushDay)
    }
    .modelContainer(SampleData.container)
    .preferredColorScheme(.dark)
}
