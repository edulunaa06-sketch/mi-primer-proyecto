import Charts
import SwiftData
import SwiftUI
import UIKit

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(StravaService.self) private var strava
    @Query private var settingsList: [UserSettings]
    @Query(sort: \StravaActivityRecord.startDate, order: .reverse) private var runs: [StravaActivityRecord]

    private var goal: Int { settingsList.first?.stepGoal ?? 8000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch health.state {
                    case .unavailable:
                        InfoBanner(text: "Este dispositivo no tiene sensor de pasos.", symbol: "heart.slash.fill", color: Theme.danger)
                    case .notDetermined:
                        permissionCard
                    case .error(let message):
                        InfoBanner(text: "Error de Salud: \(message)", symbol: "exclamationmark.triangle.fill", color: Theme.danger)
                        permissionCard
                    case .requested:
                        todayCard
                        if health.todaySteps == nil { noDataHelp }
                        historyCard
                    case .motionOnly:
                        todayCard
                        if health.motionDenied { motionHelp }
                        historyCard
                    }
                    runsCard
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Actividad")
            .refreshable { await health.refresh() }
            .task {
                await health.refreshAuthorizationState()
                if health.state == .requested || health.state == .motionOnly { await health.refresh() }
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Conectar con Apple Salud", systemImage: "heart.fill").font(.headline)
            Text("Now or Never solo LEE tus pasos de Salud para mostrarte el total diario y el historial. No escribe ni comparte datos.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            Button("Permitir acceso a pasos") { Task { await health.requestAuthorization() } }
                .buttonStyle(LimeButtonStyle())
        }
        .card()
    }

    private var todayCard: some View {
        let steps = health.todaySteps
        let fraction = steps.map { NutritionMath.progress(consumed: Double($0), target: Double(goal)) } ?? 0
        return HStack(spacing: 18) {
            ProgressRing(fraction: fraction, size: 110, label: steps == nil ? "—" : nil)
            VStack(alignment: .leading, spacing: 6) {
                Text("Pasos de hoy").font(.headline)
                Text(steps.map { NumberFormat.integer($0) } ?? "Sin datos")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                Text("Objetivo: \(NumberFormat.integer(goal))")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                if let updated = health.lastUpdated {
                    Text("Actualizado \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .card()
    }

    private var noDataHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Salud no ha devuelto pasos para hoy").font(.subheadline.weight(.semibold))
            Text("Puede que aún no hayas caminado o que el permiso esté desactivado (iOS no indica a las apps si se ha denegado la lectura). Para revisarlo:")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            Text("Ajustes › Salud › Acceso a datos y dispositivos › Now or Never › activa “Pasos”.\nTambién: app Salud › tu perfil › Apps › Now or Never.")
                .font(.footnote)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(LimeButtonStyle(filled: false))
        }
        .card()
    }

    private var motionHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activa Movimiento y forma física").font(.subheadline.weight(.semibold))
            Text("Los pasos salen del sensor del iPhone. Actívalo en Ajustes › Privacidad y seguridad › Movimiento y forma física › Now or Never.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(LimeButtonStyle(filled: false))
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: health.state == .motionOnly ? "Historial (últimos 7 días)" : "Historial (últimos 30 días)",
                          subtitle: health.state == .motionOnly ? "Pasos del sensor del iPhone" : "Solo días con datos en Salud")
            if health.history.isEmpty {
                Text("No hay datos de pasos disponibles.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                Chart {
                    ForEach(health.history) { day in
                        BarMark(x: .value("Día", day.date, unit: .day), y: .value("Pasos", day.steps))
                            .foregroundStyle(day.steps >= goal ? Theme.lime : Theme.lime.opacity(0.35))
                    }
                    RuleMark(y: .value("Objetivo", goal))
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)

                let reached = health.history.filter { $0.steps >= goal }.count
                let average = health.history.map(\.steps).reduce(0, +) / max(health.history.count, 1)
                HStack {
                    MetricTile(title: "Media diaria", value: NumberFormat.integer(average))
                    MetricTile(title: "Días con objetivo", value: "\(reached)/\(health.history.count)")
                }
                ForEach(health.history.prefix(14)) { day in
                    HStack {
                        Text(DateUtils.shortDate(day.date)).font(.subheadline)
                        Spacer()
                        Text(NumberFormat.integer(day.steps)).monospacedDigit()
                        Text(NumberFormat.percent(NutritionMath.progress(consumed: Double(day.steps), target: Double(goal))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(day.steps >= goal ? Theme.lime : Theme.textSecondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
        .card()
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Carreras de Strava")
                if case .connected = strava.status {
                    Button {
                        Task { await strava.syncRuns(into: context) }
                    } label: {
                        if strava.isWorking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            StravaLaunchButton(title: "Abrir Strava")
            switch strava.status {
            case .notConfigured:
                Text("Importación de carreras pendiente de configuración (ver Ajustes › Strava y el README).")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            case .disconnected:
                Text("Conecta tu cuenta en Ajustes › Strava para ver aquí distancia, tiempo y ritmo.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            case .connected:
                if let error = strava.lastError {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
                if runs.isEmpty {
                    Text("Sin carreras importadas todavía.").font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(runs.prefix(20)) { RunRow(run: $0) }
                }
            }
        }
        .card()
    }
}
