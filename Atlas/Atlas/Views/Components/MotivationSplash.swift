import SwiftUI

/// Frase motivadora al volver a la app tras 10 minutos o más fuera (al abrirla sale la intro de ATLAS).
/// Se cierra sola a los 4 segundos o al tocarla.
struct MotivationSplash: View {
    let quote: Motivation.Quote
    var autoDismiss = true
    let onFinish: () -> Void

    @State private var quoteVisible = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            quoteView
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            withAnimation(.easeOut(duration: 0.45)) { quoteVisible = true }
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(4))
            finish()
        }
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

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
