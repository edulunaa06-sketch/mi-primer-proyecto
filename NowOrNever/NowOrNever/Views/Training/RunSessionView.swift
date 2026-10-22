import SwiftData
import SwiftUI

struct RunSessionView: View {
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Environment(StravaService.self) private var strava
    @State private var log: WorkoutSessionLog?
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
            SectionHeader(title: "Carreras importadas de Strava")
            switch strava.status {
            case .notConfigured:
                InfoBanner(text: "Importación pendiente de configuración: requiere una app de Strava (Client ID) y un backend seguro. Consulta el README. El botón de abrir Strava funciona igualmente.")
            case .disconnected:
                InfoBanner(text: "Strava no está conectado. Conéctalo en Ajustes para importar distancia, tiempo y ritmo.", symbol: "link")
            case .connected:
                if runs.isEmpty {
                    Text("Aún no hay carreras importadas. Sincroniza desde Ajustes o desde Actividad.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(runs.prefix(3)) { RunRow(run: $0) }
                }
            }
        }
        .card()
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
