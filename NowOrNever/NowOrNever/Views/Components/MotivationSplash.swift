import SwiftUI

/// Pantalla de bienvenida. Al abrir la app: pantalla de carga con «NOW OR NEVER» (con música),
/// desaparece y sale la frase motivadora; al cerrarse, la música se apaga y aparece el menú.
/// Al volver tras un rato fuera solo sale la frase, sin música.
/// Se cierra sola o al tocarla (tocar durante el logo pasa directamente a la frase).
struct MotivationSplash: View {
    let quote: Motivation.Quote
    var autoDismiss = true
    /// true = pantalla de carga con el logo y música antes de la frase.
    var showIntro = false
    let onFinish: () -> Void

    private enum Phase { case logo, quote }

    @State private var phase: Phase = .quote
    @State private var logoVisible = false
    @State private var quoteVisible = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if phase == .logo {
                logo
            } else {
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
                IntroMusicPlayer.shared.play()
                withAnimation(.easeOut(duration: 0.7)) { logoVisible = true }
                // El ritmo de la música entra a los ~1,8 s: ahí desaparece el logo y llega la frase.
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.easeIn(duration: 0.4)) { logoVisible = false }
                try? await Task.sleep(for: .milliseconds(420))
                showQuote()
            } else {
                showQuote()
            }
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(showIntro ? 4 : 3))
            finish()
        }
    }

    private var logo: some View {
        VStack(spacing: 4) {
            Text("NOW")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("OR")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .tracking(8)
                .foregroundStyle(Theme.lime)
            Text("NEVER")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Rectangle().fill(Theme.lime).frame(width: logoVisible ? 120 : 0, height: 5)
                .padding(.top, 10)
        }
        .scaleEffect(logoVisible ? 1 : 0.82)
        .opacity(logoVisible ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now or Never")
        .accessibilityIdentifier("splash.logo")
    }

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
        withAnimation(.easeOut(duration: 0.5)) { quoteVisible = true }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        IntroMusicPlayer.shared.stop()
        onFinish()
    }
}
