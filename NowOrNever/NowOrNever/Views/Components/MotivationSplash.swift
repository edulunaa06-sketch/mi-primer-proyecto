import SwiftUI
import UIKit

/// Pantalla de bienvenida. Al abrir la app: «NOW OR NEVER» entra de golpe (con vibración y una sacudida),
/// aguanta un momento y sale disparada hacia la pantalla con un destello; después, la frase motivadora.
/// Al volver tras un rato fuera solo sale la frase.
/// Se cierra sola o al tocarla (tocar durante el logo pasa directamente a la frase).
struct MotivationSplash: View {
    let quote: Motivation.Quote
    var autoDismiss = true
    /// true = pantalla de carga con el logo antes de la frase.
    var showIntro = false
    let onFinish: () -> Void

    private enum Phase { case logo, quote }

    @State private var phase: Phase = .quote
    @State private var quoteVisible = false
    @State private var finished = false

    // Logo
    @State private var logoScale: CGFloat = 2.8
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 14
    @State private var shake: CGFloat = 0
    @State private var slashWidth: CGFloat = 0
    @State private var flash: Double = 0

    var body: some View {
        ZStack {
            if phase == .logo {
                Color.black.ignoresSafeArea()
                logo
                Theme.lime.opacity(flash).ignoresSafeArea().allowsHitTesting(false)
            } else {
                Theme.background.ignoresSafeArea()
                quoteView
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if phase == .logo { showQuote() } else { finish() }
        }
        .task {
            if showIntro {
                phase = .logo
                await playIntro()
            }
            showQuote()
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(4))
            finish()
        }
    }

    // MARK: Logo

    private var logo: some View {
        VStack(alignment: .leading, spacing: -14) {
            Text("NOW")
                .font(.system(size: 112, weight: .black).width(.compressed))
                .italic()
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                Rectangle().fill(Theme.lime).frame(width: slashWidth, height: 8)
                Text("OR")
                    .font(.system(size: 40, weight: .black).width(.compressed))
                    .italic()
                    .foregroundStyle(Theme.lime)
                Rectangle().fill(Theme.lime).frame(width: slashWidth, height: 8)
            }
            .padding(.vertical, 6)
            Text("NEVER")
                .font(.system(size: 112, weight: .black).width(.compressed))
                .italic()
                .foregroundStyle(Theme.lime)
                .shadow(color: Theme.lime.opacity(0.55), radius: 18)
        }
        .rotationEffect(.degrees(-6))
        .scaleEffect(logoScale)
        .blur(radius: logoBlur)
        .opacity(logoOpacity)
        .offset(x: shake)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now or Never")
        .accessibilityIdentifier("splash.logo")
    }

    /// Entra de golpe → vibración y sacudida → aguanta → sale disparado hacia la pantalla con un destello.
    private func playIntro() async {
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            logoScale = 1
            logoOpacity = 1
            logoBlur = 0
        }
        try? await Task.sleep(for: .milliseconds(170))
        guard phase == .logo else { return }
        impact.impactOccurred(intensity: 1)
        for x in [-14.0, 11, -7, 4, 0] {
            withAnimation(.linear(duration: 0.04)) { shake = x }
            try? await Task.sleep(for: .milliseconds(40))
        }
        withAnimation(.easeOut(duration: 0.3)) { slashWidth = 54 }
        try? await Task.sleep(for: .milliseconds(1000))
        guard phase == .logo else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeIn(duration: 0.32)) {
            logoScale = 7
            logoBlur = 22
            logoOpacity = 0
            flash = 0.85
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
    }

    // MARK: Frase

    private var quoteView: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("NOW OR NEVER")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.lime)
            Rectangle().fill(Theme.lime).frame(width: 48, height: 4)
            Text(quote.text)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("splash.quote")
            if let author = quote.author {
                Text("— \(author)").font(.headline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("Toca para empezar")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .opacity(quoteVisible ? 1 : 0)
        .offset(y: quoteVisible ? 0 : 16)
    }

    private func showQuote() {
        guard phase != .quote || !quoteVisible else { return }
        phase = .quote
        withAnimation(.easeOut(duration: 0.45)) { quoteVisible = true }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
