import SwiftData
import SwiftUI

/// Un día de deporte: carrera, ciclismo, fútbol, MMA… Todos funcionan igual que funcionaba
/// la carrera (lo grabas en Strava y aquí se importa, o lo apuntas a mano), cambiando el
/// nombre y qué actividades se consideran de ese deporte.
///
/// Strava NO publica enlaces profundos por deporte, así que el botón abre Strava y ya; la
/// sección del deporte es esta pantalla, que enseña solo lo suyo.
struct SportSessionView: View {
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Environment(StravaService.self) private var strava
    @State private var log: WorkoutSessionLog?
    @State private var showManual = false
    @State private var pendingDelete: StravaActivityRecord?
    @Query(sort: \StravaActivityRecord.startDate, order: .reverse) private var activities: [StravaActivityRecord]

    private var kind: SessionKind { session.kind }

    /// Solo lo de este deporte: lo importado de Strava con sus tipos y lo apuntado a mano
    /// con su etiqueta.
    private var mine: [StravaActivityRecord] {
        let types = kind.activityTypes
        return activities.filter { types.contains($0.sportType) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(session.title, systemImage: kind.symbol)
                        .font(.title3.bold())
                    if !session.detail.isEmpty {
                        Text(session.detail).foregroundStyle(Theme.textSecondary)
                    }
                    StravaLaunchButton(title: "Abrir Strava y registrar \(kind.activityName)")
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Cómo registrarlo en Strava")
                    step(1, "Pulsa el botón para abrir Strava.")
                    step(2, "En Strava, pulsa “Grabar” y elige \(stravaNombre).")
                    step(3, "Al terminar, detén y GUARDA la actividad en Strava.")
                    step(4, "Vuelve aquí y marca la sesión como completada.")
                }
                .card()

                if let log { completion(log) }

                historial
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            log = DataStore.fetchOrCreateLog(for: session, weekStart: weekStart, in: context)
        }
        .sheet(isPresented: $showManual) { ManualActivitySheet(kind: kind) }
        .confirmationDialog("¿Borrar esto que apuntaste a mano?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let run = pendingDelete { context.delete(run); try? context.save() }
                pendingDelete = nil
            }
        }
    }

    /// Cómo se llama ese deporte dentro de Strava, para que la instrucción sea fiel.
    private var stravaNombre: String {
        kind.stravaTypes.isEmpty ? "el tipo que más se parezca" : kind.label
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.heavy))
                .frame(width: 22, height: 22)
                .background(Theme.accentDim, in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text).font(.subheadline)
        }
    }

    private func completion(_ log: WorkoutSessionLog) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation {
                    log.isCompleted.toggle()
                    log.completedAt = log.isCompleted ? Date() : nil
                    log.lastModified = Date()
                }
                try? context.save()
            } label: {
                Label(log.isCompleted ? "Sesión completada · Deshacer" : "Marcar sesión completada",
                      systemImage: log.isCompleted ? "checkmark.seal.fill" : "flag.checkered")
            }
            .buttonStyle(ActionButtonStyle(filled: !log.isCompleted))
            Text("Esta sesión tiene su propio estado, independiente de cualquier otra sesión del día.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var historial: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tu \(kind.activityName)",
                          subtitle: kind == .run ? "Cuenta para los km del resumen semanal y las medallas" : nil)
            Button { showManual = true } label: {
                Label("Apuntarlo a mano", systemImage: "square.and.pencil")
            }
            .buttonStyle(ActionButtonStyle(filled: false))

            if kind.stravaTypes.isEmpty {
                InfoBanner(text: "Strava no distingue \(kind.label), así que esto no se importa solo: apúntalo a mano y se guarda aquí.",
                           symbol: "info.circle.fill")
            } else {
                switch strava.status {
                case .notConfigured:
                    InfoBanner(text: "Para importar de Strava, configúralo una vez en Ajustes › Strava (hay una guía paso a paso). Mientras, puedes apuntarlo a mano.")
                case .disconnected:
                    InfoBanner(text: "Strava no está conectado. Conéctalo en Ajustes para importar distancia y tiempo, o apúntalo a mano.", symbol: "link")
                case .connected:
                    EmptyView()
                }
            }

            if mine.isEmpty {
                Text("Todavía no hay nada apuntado.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(mine.prefix(5)) { run in
                    ActivityRow(run: run, showsDistance: kind.hasDistance)
                        .contextMenu {
                            if run.isManual {
                                Button("Borrar", systemImage: "trash", role: .destructive) { pendingDelete = run }
                            }
                        }
                }
                if mine.contains(where: \.isManual) {
                    Text("Mantén pulsado lo que apuntaste a mano para borrarlo.").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()
    }
}

/// Apuntar una actividad sin Strava. En los deportes que se miden en kilómetros pide
/// distancia y tiempo; en los demás, solo el tiempo.
struct ManualActivitySheet: View {
    let kind: SessionKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var km: Double?
    @State private var minutes: Int?
    @State private var seconds: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    if kind.hasDistance {
                        HStack {
                            Text("Distancia (km)")
                            Spacer()
                            DecimalField(placeholder: "0,0", value: $km, width: 100)
                        }
                    }
                    HStack {
                        Text("Tiempo")
                        Spacer()
                        IntField(placeholder: "min", value: $minutes, width: 64)
                        Text(":")
                        IntField(placeholder: "s", value: $seconds, width: 56)
                    }
                    if kind.hasDistance, let km, km > 0, let total = totalSeconds, total > 0 {
                        LabeledContent("Ritmo medio", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: km * 1000, seconds: total)))
                    }
                } footer: {
                    Text("Usa los datos de tu reloj o de la app con la que lo hiciste. Se guarda solo en este iPhone.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .screenBackground()
            .navigationTitle("Apuntar \(kind.activityName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(!puedeGuardar) }
            }
        }
    }

    private var totalSeconds: Int? {
        guard minutes != nil || seconds != nil else { return nil }
        return (minutes ?? 0) * 60 + (seconds ?? 0)
    }

    private var puedeGuardar: Bool {
        kind.hasDistance ? km != nil : totalSeconds != nil
    }

    private func save() {
        var metros: Double = 0
        if kind.hasDistance {
            guard let km, (0.1...300).contains(km) else {
                errorMessage = "Introduce una distancia entre 0,1 y 300 km."
                return
            }
            metros = km * 1000
        }
        guard let total = totalSeconds, total >= 60, (seconds ?? 0) < 60 else {
            errorMessage = "Introduce el tiempo en minutos y segundos (los segundos, de 0 a 59)."
            return
        }
        // Id negativo: así nunca choca con una actividad importada de Strava.
        let id = -Int64(Date().timeIntervalSince1970 * 1000)
        context.insert(StravaActivityRecord(stravaID: id,
                                            name: "\(kind.label) apuntado a mano",
                                            sportType: kind.manualStravaType,
                                            startDate: date,
                                            distanceMeters: metros,
                                            movingTimeSeconds: total,
                                            elapsedTimeSeconds: total,
                                            elevationGainMeters: nil))
        try? context.save()
        dismiss()
    }
}

struct ActivityRow: View {
    let run: StravaActivityRecord
    /// En los deportes sin kilómetros no se enseña distancia ni ritmo: serían siempre cero.
    var showsDistance = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(DateUtils.shortDate(run.startDate)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 14) {
                if showsDistance { stat("Distancia", RunMath.formatKm(run.distanceMeters)) }
                stat("Movimiento", RunMath.formatDuration(run.movingTimeSeconds))
                stat("Total", RunMath.formatDuration(run.elapsedTimeSeconds))
            }
            if showsDistance {
                HStack(spacing: 14) {
                    stat("Ritmo medio", RunMath.formatPace(run.paceSecondsPerKm))
                    stat("Desnivel", run.elevationGainMeters.map { "\(Int($0.rounded())) m" } ?? "—")
                }
            }
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(Theme.textTertiary)
            Text(value).font(.footnote.weight(.semibold).monospacedDigit())
        }
    }
}
