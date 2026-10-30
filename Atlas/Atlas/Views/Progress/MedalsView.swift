import SwiftData
import SwiftUI
import UIKit

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
    /// Medallas que acaban de subir de nivel (se celebran una sola vez).
    @State private var celebrating: Set<String> = []
    @State private var banner: Medal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let seenKey = "medals.seenTiers"

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
                    MetricTile(title: "Medallas", value: "\(earned.count)/\(list.count)", detail: "Conseguidas", symbol: "medal.fill",
                               symbolColor: Theme.gold)
                    MetricTile(title: "De oro", value: "\(list.filter { $0.tier == .gold }.count)",
                               detail: "Nivel máximo", symbol: "star.fill", symbolColor: Theme.gold)
                }
                if let banner {
                    Label("¡Medalla desbloqueada! \(banner.title) · \(banner.tier.label)", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.background)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("medals.unlocked")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(list) { MedalCard(medal: $0, celebrate: celebrating.contains($0.id)) }
                }
                InfoBanner(text: "Pasos: sensor del iPhone (Apple Salud no se puede leer al instalar la app con una cuenta de Apple gratuita). Carreras: Strava si lo conectas en Ajustes, o las que apuntes a mano en Entreno › sesión de carrera. Cada medalla tiene tres niveles: bronce, plata y oro.",
                           symbol: "info.circle.fill", color: Theme.gold)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear { trackingStart = DataStore.trackingStart(context) }
        .task(id: signature) {
            let computed = computeMedals()
            medals = computed
            await celebrateNewOnes(computed)
        }
    }

    /// Compara con los niveles ya vistos en este iPhone: cada medalla nueva se celebra una sola vez.
    /// La primera vez se guardan las que ya tenías sin celebrar.
    private func celebrateNewOnes(_ computed: [Medal]) async {
        let defaults = UserDefaults.standard
        let seen = defaults.data(forKey: Self.seenKey).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) }
        let fresh = MedalUnlocks.newlyUnlocked(computed, seen: seen)
        if let data = try? JSONEncoder().encode(MedalUnlocks.updatedSeen(computed, seen: seen)) {
            defaults.set(data, forKey: Self.seenKey)
        }
        guard !fresh.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) {
            celebrating = Set(fresh.map(\.id))
            banner = fresh.max { $0.tier < $1.tier }
        }
        try? await Task.sleep(for: .seconds(3.5))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
            banner = nil
            celebrating = []
        }
    }
}

/// Medalla: dorada si está conseguida (más brillante cuanto más alto el nivel, con 1–3 estrellas),
/// gris si está pendiente. Icono, nombre, descripción, mejor marca y lo que falta para el siguiente nivel.
struct MedalCard: View {
    let medal: Medal
    var celebrate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop = false

    /// Cada metal con su color de verdad: bronce marrón, plata gris y oro dorado. Antes la
    /// plata salía dorada y el oro en un amarillo clarito que sobre papel blanco no se veía.
    static func color(_ tier: MedalTier) -> Color {
        switch tier {
        case .locked: return Theme.textTertiary
        case .bronze: return Color(red: 0.62, green: 0.38, blue: 0.16)
        case .silver: return DS.steel
        case .gold: return Theme.gold
        }
    }

    private var unlocked: Bool { medal.tier != .locked }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(unlocked ? Self.color(medal.tier).opacity(0.18) : Theme.cardRaised)
                Circle().strokeBorder(unlocked ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.cardRaised),
                                      lineWidth: medal.tier == .gold ? 4 : 3)
                Image(systemName: unlocked ? medal.symbol : "lock.fill")
                    .font(.system(size: unlocked ? 24 : 18, weight: .bold))
                    .foregroundStyle(unlocked ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.textTertiary))
            }
            .frame(width: 64, height: 64)
            .shadow(color: medal.tier == .gold || celebrate ? Theme.gold.opacity(0.45) : .clear, radius: celebrate ? 14 : 8)
            .scaleEffect(pop ? 1.15 : 1)
            Text(medal.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            HStack(spacing: 2) {
                if unlocked {
                    ForEach(0..<medal.tier.rawValue, id: \.self) { _ in
                        Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    }
                }
                Text(unlocked ? medal.tier.label.uppercased() : "PENDIENTE")
                    .font(.caption2.weight(.heavy)).tracking(1)
            }
            .foregroundStyle(unlocked ? Self.color(medal.tier) : Theme.textSecondary)
            Text(medal.summary)
                .font(.caption2).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(medal.value ?? "Sin datos todavía")
                .font(.caption.weight(unlocked ? .bold : .regular).monospacedDigit())
                .foregroundStyle(medal.value == nil ? Theme.textTertiary : (unlocked ? Theme.gold : Theme.textPrimary))
                .multilineTextAlignment(.center)
            if let date = medal.date {
                Text(DateUtils.shortDate(date)).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            if let next = medal.nextGoal {
                VStack(spacing: 4) {
                    ProgressBar(fraction: medal.progress, height: 5, color: Theme.gold.opacity(unlocked ? 1 : 0.6))
                    Text(next).font(.caption2).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .top)
        .card(padding: 12)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.gold.opacity(celebrate ? 0.9 : (unlocked ? 0.25 : 0)), lineWidth: celebrate ? 2 : 1)
        }
        .onChange(of: celebrate) { _, now in
            guard now, !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pop = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.35)) { pop = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(medal.title): \(unlocked ? medal.tier.label : "pendiente"). \(medal.summary) \(medal.value ?? "Sin datos")")
    }
}
