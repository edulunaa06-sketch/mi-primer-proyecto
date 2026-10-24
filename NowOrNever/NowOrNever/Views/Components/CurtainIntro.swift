import SwiftUI
import UIKit

/// Pantalla de inicio al abrir la app, como un telón:
/// 1. Todo negro. «NOW» baja desde arriba, «NEVER» sube desde abajo y «OR» aparece en el centro de borroso a nítido.
/// 2. Aguanta un momento (con vibración).
/// 3. El telón se abre: la mitad de arriba se va hacia arriba con «NOW», la de abajo hacia abajo con «NEVER»
///    y «OR» se desvanece; detrás ya está la app.
/// Tocar la pantalla abre el telón al momento. Con «Reducir movimiento» solo hay fundidos.
struct CurtainIntro: View {
    /// false = se queda cerrado (solo para las capturas del CI).
    var autoOpen = true
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wordsIn = false
    @State private var opened = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.height / 2
            // Lo que se mueve en el telón (si el telón se abre, cada mitad recorre su propia altura y algo más).
            let travel = half + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom + 40
            ZStack {
                VStack(spacing: 0) {
                    // Mitad de arriba con «NOW» pegado al centro.
                    Theme.background
                        .overlay(alignment: .bottom) {
                            word("NOW", color: Theme.textPrimary)
                                .offset(y: wordsIn || reduceMotion ? -30 : -travel)
                        }
                        .frame(height: half + geo.safeAreaInsets.top)
                        .offset(y: opened && !reduceMotion ? -travel : 0)
                    // Mitad de abajo con «NEVER» pegado al centro.
                    Theme.background
                        .overlay(alignment: .top) {
                            word("NEVER", color: Theme.lime)
                                .shadow(color: Theme.lime.opacity(0.5), radius: 16)
                                .offset(y: wordsIn || reduceMotion ? 30 : travel)
                        }
                        .frame(height: half + geo.safeAreaInsets.bottom)
                        .offset(y: opened && !reduceMotion ? travel : 0)
                }
                .clipped()
                // «OR» en el centro: de borroso a nítido al entrar, y se difumina al abrir.
                Text("OR")
                    .font(.system(size: 34, weight: .black).width(.compressed))
                    .italic()
                    .tracking(4)
                    .foregroundStyle(Theme.lime)
                    .blur(radius: wordsIn && !opened ? 0 : 18)
                    .opacity(wordsIn && !opened ? 1 : 0)
                    .scaleEffect(opened ? 1.6 : 1)
                    .accessibilityHidden(true)
            }
            .opacity(reduceMotion && opened ? 0 : 1)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now or Never")
        .accessibilityIdentifier("splash.logo")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .task { await play() }
    }

    private func word(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 112, weight: .black).width(.compressed))
            .italic()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 24)
            .opacity(reduceMotion && !wordsIn ? 0 : 1)
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(150))
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        withAnimation(reduceMotion ? .easeIn(duration: 0.3) : .spring(response: 0.55, dampingFraction: 0.78)) { wordsIn = true }
        try? await Task.sleep(for: .milliseconds(450))
        impact.impactOccurred(intensity: 1)
        guard autoOpen else { return }
        try? await Task.sleep(for: .milliseconds(1100))
        open()
    }

    private func open() {
        guard !opened else { return }
        if !wordsIn { wordsIn = true }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeInOut(duration: 0.6)) { opened = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 320 : 620))
            guard !finished else { return }
            finished = true
            onFinish()
        }
    }
}
