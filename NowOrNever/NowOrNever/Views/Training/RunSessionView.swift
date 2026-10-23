import SwiftData
import SwiftUI

struct RunSessionView: View {
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Environment(StravaService.self) private var strava
    @State private var log: WorkoutSessionLog?
    @State private var showManualRun = false
    @State private var pendingDelete: StravaActivityRecord?
    @Query(sort: \StravaActivityRecord.startDate, order: .reverse) private var runs: [StravaActivityRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(session.title, systemImage: "figure.run")
                        .font(.title3.bold())
                    Text(session.detail)
                        .foregroundStyle(Theme.textSecondary)
                    StravaLaunchButton()
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Cómo registrar la carrera")
                    step(1, "Pulsa el botón para abrir Strava.")
                    step(2, "En Strava, pulsa “Grabar” y elige Carrera.")
                    step(3, "Al terminar, detén y GUARDA la actividad en Strava.")
                    step(4, "Vuelve aquí y marca la sesión como completada.")
                }
                .card()

                if let log { completion(log) }

                recentRuns
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            log = DataStore.fetchOrCreateLog(for: session, weekStart: weekStart, in: context)
        }
        .sheet(isPresented: $showManualRun) { ManualRunSheet() }
        .confirmationDialog("¿Borrar esta carrera apuntada a mano?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let run = pendingDelete { context.delete(run); try? context.save() }
                pendingDelete = nil
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.heavy))
                .frame(width: 22, height: 22)
                .background(Theme.limeDim, in: Circle())
                .foregroundStyle(Theme.lime)
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
                Label(log.isCompleted ? "Carrera completada · Deshacer" : "Marcar carrera completada",
                      systemImage: log.isCompleted ? "checkmark.seal.fill" : "flag.checkered")
            }
            .buttonStyle(LimeButtonStyle(filled: !log.isCompleted))
            Text("Esta sesión tiene su propio estado, independiente de cualquier otra sesión del día.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tus carreras", subtitle: "Cuentan para los km del resumen semanal y las medallas")
            Button { showManualRun = true } label: {
                Label("Apuntar carrera a mano", systemImage: "square.and.pencil")
            }
            .buttonStyle(LimeButtonStyle(filled: false))
            switch strava.status {
            case .notConfigured:
                InfoBanner(text: "Importar de Strava está pendiente de configuración (requiere una app de Strava y un backend; ver README). Mientras, puedes apuntar tus carreras a mano.")
            case .disconnected:
                InfoBanner(text: "Strava no está conectado. Conéctalo en Ajustes para importar distancia, tiempo y ritmo, o apunta la carrera a mano.", symbol: "link")
            case .connected:
                EmptyView()
            }
            if runs.isEmpty {
                Text("Aún no hay carreras registradas.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(runs.prefix(5)) { run in
                    RunRow(run: run)
                        .contextMenu {
                            if run.isManual {
                                Button("Borrar", systemImage: "trash", role: .destructive) { pendingDelete = run }
                            }
                        }
                }
                if runs.contains(where: \.isManual) {
                    Text("Mantén pulsada una carrera apuntada a mano para borrarla.").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()
    }
}

/// Apuntar una carrera sin Strava: fecha, distancia y tiempo.
struct ManualRunSheet: View {
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
                    HStack {
                        Text("Distancia (km)")
                        Spacer()
                        DecimalField(placeholder: "0,0", value: $km, width: 100)
                    }
                    HStack {
                        Text("Tiempo")
                        Spacer()
                        IntField(placeholder: "min", value: $minutes, width: 64)
                        Text(":")
                        IntField(placeholder: "s", value: $seconds, width: 56)
                    }
                    if let km, km > 0, let total = totalSeconds, total > 0 {
                        LabeledContent("Ritmo medio", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: km * 1000, seconds: total)))
                    }
                } footer: {
                    Text("Usa los datos de tu reloj o de la app con la que corriste. Se guarda solo en este iPhone.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .screenBackground()
            .navigationTitle("Apuntar carrera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(km == nil) }
            }
        }
    }

    private var totalSeconds: Int? {
        guard minutes != nil || seconds != nil else { return nil }
        return (minutes ?? 0) * 60 + (seconds ?? 0)
    }

    private func save() {
        guard let km, (0.1...300).contains(km) else {
            errorMessage = "Introduce una distancia entre 0,1 y 300 km."
            return
        }
        guard let total = totalSeconds, total >= 60, (seconds ?? 0) < 60 else {
            errorMessage = "Introduce el tiempo en minutos y segundos (los segundos, de 0 a 59)."
            return
        }
        // Id negativo: así nunca choca con una actividad importada de Strava.
        let id = -Int64(Date().timeIntervalSince1970 * 1000)
        context.insert(StravaActivityRecord(stravaID: id, name: "Carrera apuntada a mano", sportType: "Run", startDate: date,
                                            distanceMeters: km * 1000, movingTimeSeconds: total, elapsedTimeSeconds: total,
                                            elevationGainMeters: nil))
        try? context.save()
        dismiss()
    }
}

struct RunRow: View {
    let run: StravaActivityRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(DateUtils.shortDate(run.startDate)).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 14) {
                stat("Distancia", RunMath.formatKm(run.distanceMeters))
                stat("Movimiento", RunMath.formatDuration(run.movingTimeSeconds))
                stat("Total", RunMath.formatDuration(run.elapsedTimeSeconds))
            }
            HStack(spacing: 14) {
                stat("Ritmo medio", RunMath.formatPace(run.paceSecondsPerKm))
                stat("Desnivel", run.elevationGainMeters.map { "\(Int($0.rounded())) m" } ?? "—")
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
