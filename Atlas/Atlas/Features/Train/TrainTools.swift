import SwiftUI
import UIKit
import UserNotifications

// MARK: - Temporizador de descanso

/// Cuenta atrás entre series. Empieza sola al marcar una serie; vibra al acabar y, si la app está
/// en segundo plano o el iPhone bloqueado, avisa con una notificación (si están permitidas).
@MainActor
@Observable
final class RestTimer {
    private(set) var endsAt: Date?
    private(set) var total: Int = 0
    private var task: Task<Void, Never>?
    private static let notificationID = "atlas.rest.timer"

    var isRunning: Bool { endsAt != nil }

    func start(seconds: Int) {
        total = seconds
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        schedule()
    }

    func add(_ seconds: Int) {
        guard let end = endsAt else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > Date() else { stop(); return }
        endsAt = newEnd
        total = max(total + seconds, 1)
        schedule()
    }

    func stop() {
        task?.cancel()
        endsAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func schedule() {
        task?.cancel()
        guard let end = endsAt else { return }
        let wait = end.timeIntervalSinceNow
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(wait, 0)))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self?.endsAt = nil
        }
        let content = UNMutableNotificationContent()
        content.title = "Descanso terminado"
        content.body = "A por la siguiente serie."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(wait, 1), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}

struct RestTimerBar: View {
    let timer: RestTimer

    var body: some View {
        if let end = timer.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(Int(end.timeIntervalSince(context.date).rounded(.up)), 0)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(DS.surfaceHi, lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: timer.total > 0 ? CGFloat(left) / CGFloat(timer.total) : 0)
                            .stroke(DS.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: left)
                        Image(systemName: "timer").font(.caption.weight(.bold)).foregroundStyle(DS.cyan)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DESCANSO").font(.caption2.weight(.heavy)).foregroundStyle(DS.text2)
                        Text(RestTimerLogic.format(left))
                            .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .accessibilityIdentifier("rest.time")
                    }
                    Spacer()
                    button("−15") { timer.add(-15) }
                    button("+15") { timer.add(15) }
                    Button { timer.stop() } label: {
                        Image(systemName: "forward.end.fill").font(.subheadline.weight(.bold))
                            .frame(width: 40, height: 36)
                            .background(DS.cyan, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Color.black)
                    }
                    .accessibilityLabel("Saltar descanso")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(red: 0.08, green: 0.085, blue: 0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.cyan.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 44, height: 36)
                .background(DS.surfaceHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calculadora de discos y calentamiento

struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var target: Double?
    @State private var bar: Double = 20

    private var weight: Double { target ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    platesCard
                    warmupCard
                }
                .padding(16)
            }
            .background(AtlasBackground())
            .navigationTitle("Discos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PESO TOTAL").font(.caption.weight(.heavy)).foregroundStyle(DS.text2)
            HStack {
                NumberField(placeholder: "kg", value: $target, width: 120)
                    .accessibilityIdentifier("plates.target")
                Text("kg").foregroundStyle(DS.text2)
                Spacer()
            }
            Picker("Barra", selection: $bar) {
                Text("Barra 20 kg").tag(20.0)
                Text("15 kg").tag(15.0)
                Text("10 kg (EZ)").tag(10.0)
            }
            .pickerStyle(.segmented)
        }
        .glass()
    }

    private var platesCard: some View {
        let result = PlateCalculator.load(target: weight, bar: bar)
        let perSideText: String = result.perSide.map { NumberFormat.kg($0) }.joined(separator: " + ") + " kg en cada lado"
        let emptyText: String = (weight > 0 && weight <= bar) ? "Solo la barra." : "Escribe el peso total."
        return VStack(alignment: .leading, spacing: 12) {
            Text("DISCOS POR LADO").font(.caption.weight(.heavy)).foregroundStyle(DS.text2)
            if result.perSide.isEmpty {
                Text(emptyText).foregroundStyle(DS.text2)
            } else {
                barView(result.perSide)
                Text(perSideText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityIdentifier("plates.perSide")
            }
            if result.isApproximate && weight > bar {
                Label("Con discos normales lo más cerca es \(NumberFormat.kg(result.total)) kg.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(DS.warn)
            }
        }
        .glass()
    }

    @ViewBuilder
    private var warmupCard: some View {
        let warmup: [SetSample] = Warmup.sets(working: weight, bar: bar)
        if !warmup.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CALENTAMIENTO").font(.caption.weight(.heavy)).foregroundStyle(DS.text2)
                ForEach(Array(warmup.enumerated()), id: \.offset) { item in
                    warmupRow(item.offset, item.element)
                }
                Text("Después, tus series de trabajo a \(NumberFormat.kg(weight)) kg.")
                    .font(.caption).foregroundStyle(DS.text2)
            }
            .glass()
        }
    }

    private func warmupRow(_ i: Int, _ s: SetSample) -> some View {
        HStack {
            Text("\(i + 1)").font(.caption.weight(.heavy)).frame(width: 22, height: 22)
                .background(DS.cyan.opacity(0.16), in: Circle()).foregroundStyle(DS.cyan)
            Text("\(NumberFormat.kg(s.kg)) kg × \(s.reps)").font(.subheadline.monospacedDigit())
            Spacer()
        }
    }

    /// Dibujo de un lado de la barra con los discos a escala.
    private func barView(_ plates: [Double]) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(DS.text3).frame(width: 34, height: 8)
            RoundedRectangle(cornerRadius: 2).fill(DS.text2).frame(width: 8, height: 26)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, p in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(p))
                    .frame(width: p >= 10 ? 14 : 10, height: 34 + 70 * CGFloat(min(p, 25) / 25))
                    .overlay(Text(NumberFormat.kg(p)).font(.system(size: 7, weight: .heavy)).rotationEffect(.degrees(-90))
                        .foregroundStyle(.white).fixedSize())
            }
            Rectangle().fill(DS.text3).frame(width: 30, height: 8)
            Spacer(minLength: 0)
        }
        .frame(height: 110)
        .accessibilityHidden(true)
    }

    /// Colores de discos olímpicos.
    private func color(_ p: Double) -> Color {
        switch p {
        case 25: return Color(red: 0.85, green: 0.15, blue: 0.15)
        case 20: return Color(red: 0.15, green: 0.35, blue: 0.9)
        case 15: return Color(red: 0.95, green: 0.75, blue: 0.1)
        case 10: return Color(red: 0.2, green: 0.65, blue: 0.3)
        case 5: return Color(white: 0.85)
        default: return Color(white: 0.45)
        }
    }
}

