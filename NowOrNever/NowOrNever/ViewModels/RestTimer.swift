import Foundation
import Observation
import SwiftUI
import UIKit

/// Temporizador de descanso entre series.
@Observable
final class RestTimer {
    private(set) var remaining: Int = 0
    private(set) var total: Int = 0
    private(set) var isRunning = false
    /// Nombre del ejercicio que lo ha lanzado, para enseñarlo en la barra.
    private(set) var exerciseName: String = ""

    @ObservationIgnored private var timer: Timer?

    var isActive: Bool { isRunning || remaining > 0 }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }

    var text: String { DateHelper.timerText(remaining) }

    func start(seconds: Int, exercise: String) {
        stopTimer()
        total = max(1, seconds)
        remaining = total
        exerciseName = exercise
        isRunning = true
        startTimer()
    }

    func toggle() {
        guard remaining > 0 else { return }
        isRunning.toggle()
        isRunning ? startTimer() : stopTimer()
    }

    /// Suma o resta segundos sobre la marcha.
    func adjust(by seconds: Int) {
        guard isActive else { return }
        remaining = max(0, remaining + seconds)
        total = max(total, remaining)
        if remaining == 0 { finish() }
    }

    func cancel() {
        stopTimer()
        remaining = 0
        total = 0
        isRunning = false
        exerciseName = ""
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func tick() {
        guard isRunning else { return }
        if remaining > 1 {
            remaining -= 1
        } else {
            remaining = 0
            finish()
        }
    }

    private func finish() {
        stopTimer()
        isRunning = false
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// Barra inferior con el tiempo de descanso.
struct RestTimerBar: View {
    @Bindable var timer: RestTimer

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DESCANSO")
                        .font(Theme.overline)
                        .kerning(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(timer.exerciseName)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(timer.text)
                    .font(Theme.hero(34))
                    .foregroundStyle(timer.remaining == 0 ? Theme.accent : Theme.text)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardElevated)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(3, geometry.size.width * (1 - timer.progress)))
                }
            }
            .frame(height: 6)

            HStack(spacing: 10) {
                Button("-30 s") { timer.adjust(by: -30) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(timer.isRunning ? "Pausa" : "Seguir") { timer.toggle() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("+30 s") { timer.adjust(by: 30) }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    timer.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 42)
                        .background(Theme.cardElevated)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1.2)
        )
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.5), radius: 14, y: -4)
    }
}

/// Vista de apoyo para la preview.
private struct RestTimerPreview: View {
    @State private var timer = RestTimer()

    var body: some View {
        VStack {
            Spacer()
            RestTimerBar(timer: timer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear { timer.start(seconds: 150, exercise: "Press banca") }
    }
}

#Preview {
    RestTimerPreview()
        .preferredColorScheme(.dark)
}
