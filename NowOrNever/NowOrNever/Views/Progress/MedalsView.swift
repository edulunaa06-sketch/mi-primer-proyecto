import SwiftData
import SwiftUI

/// Medallas por logros (bronce, plata y oro) calculadas con tus datos reales.
struct MedalsView: View {
    @Environment(\.modelContext) private var context
    @Query private var meals: [MealRecord]
    @Query private var logs: [WorkoutSessionLog]
    @Query private var dailySteps: [DailySteps]
    @Query private var marks: [DayMarkRecord]
    @Query private var settingsList: [UserSettings]
    @Query private var weights: [WeightEntry]
    @Query private var runs: [StravaActivityRecord]
    @Query private var photos: [ProgressPhoto]

    @State private var trackingStart = DateUtils.startOfDay(Date())

    /// Se calculan una vez (y de nuevo solo si cambian los datos), no en cada redibujado.
    @State private var medals: [Medal] = []

    private var signature: String {
        TrackingSnapshot.signature(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                   stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
            + "|\(weights.count)|\(runs.count)|\(photos.count)"
    }

    private func computeMedals() -> [Medal] {
        let snapshot = TrackingSnapshot(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                        stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
        var photoMonths: [String: Set<String>] = [:]
        for p in photos { photoMonths["\(p.year)-\(p.month)", default: []].insert(p.viewRaw) }
        let strength = logs.filter { $0.isCompleted && WeeklyRoutine.session(id: $0.sessionID)?.kind == .strength }
        let input = MedalInput(
            runs: runs.filter { StravaAPI.runSportTypes.contains($0.sportType) || $0.isManual }.map(\.sample),
            dailySteps: snapshot.allDailySteps,
            bestStreak: snapshot.streak.best,
            strengthSessions: strength.count,
            weighIns: weights.count,
            completePhotoMonths: photoMonths.values.filter { $0.count >= PhotoView.allCases.count }.count)
        return Medals.all(input)
    }

    var body: some View {
        let list = medals.isEmpty ? Medals.all(MedalInput()) : medals
        let earned = list.filter { $0.tier != .locked }
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    MetricTile(title: "Medallas", value: "\(earned.count)/\(list.count)", detail: "Conseguidas", symbol: "medal.fill")
                    MetricTile(title: "De oro", value: "\(list.filter { $0.tier == .gold }.count)",
                               detail: "Nivel máximo", symbol: "star.fill")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(list) { MedalCard(medal: $0) }
                }
                InfoBanner(text: "Pasos: sensor del iPhone (Apple Salud no se puede leer al instalar la app con una cuenta de Apple gratuita). Carreras: Strava si lo conectas en Ajustes, o las que apuntes a mano en Entreno › sesión de carrera. Cada medalla tiene tres niveles: bronce, plata y oro.",
                           symbol: "info.circle.fill", color: Theme.lime)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear { trackingStart = DataStore.trackingStart(context) }
        .task(id: signature) { medals = computeMedals() }
    }
}

struct MedalCard: View {
    let medal: Medal

    static func color(_ tier: MedalTier) -> Color {
        switch tier {
        case .locked: return Theme.cardRaised
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.22)
        // Sobre fondo blanco (versión Daniela) la plata y el oro van más oscuros para que se vean.
        case .silver: return Theme.isLight ? Color(red: 0.52, green: 0.55, blue: 0.60) : Color(red: 0.78, green: 0.80, blue: 0.84)
        case .gold: return Theme.isLight ? Color(red: 0.85, green: 0.62, blue: 0.0) : Color(red: 1.0, green: 0.80, blue: 0.15)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Self.color(medal.tier).opacity(medal.tier == .locked ? 1 : 0.22))
                Circle().stroke(Self.color(medal.tier), lineWidth: 3)
                Image(systemName: medal.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(medal.tier == .locked ? Theme.textTertiary : Self.color(medal.tier))
            }
            .frame(width: 64, height: 64)
            Text(medal.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            Text(medal.tier.label.uppercased())
                .font(.caption2.weight(.heavy)).tracking(1)
                .foregroundStyle(medal.tier == .locked ? Theme.textTertiary : Self.color(medal.tier))
            Text(medal.value ?? "Sin datos todavía")
                .font(.caption.monospacedDigit())
                .foregroundStyle(medal.value == nil ? Theme.textTertiary : Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let date = medal.date {
                Text(DateUtils.shortDate(date)).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            if let next = medal.nextGoal {
                VStack(spacing: 4) {
                    ProgressBar(fraction: medal.progress, height: 5)
                    Text(next).font(.caption2).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .top)
        .card(padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(medal.title): \(medal.tier.label). \(medal.value ?? "Sin datos")")
    }
}
