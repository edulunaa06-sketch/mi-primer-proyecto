import SwiftUI

/// Pantalla de bienvenida con una frase motivadora. Aparece al abrir la app y al volver tras un rato fuera;
/// se cierra sola a los 3 segundos o al tocarla, y deja paso a la interfaz.
struct MotivationSplash: View {
    let quote: Motivation.Quote
    var autoDismiss = true
    let onFinish: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
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
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .task {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            guard autoDismiss else { return }
            try? await Task.sleep(for: .seconds(3))
            onFinish()
        }
    }
}
