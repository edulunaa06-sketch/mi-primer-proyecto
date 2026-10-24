import SwiftUI

/// Marca de ATLAS: una «A» que es a la vez una cima y una barra olímpica (la barra cruza la A con sus discos).
struct AtlasMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // Patas de la A (la cima).
        p.move(to: CGPoint(x: r.minX + w * 0.16, y: r.minY + h * 0.88))
        p.addLine(to: CGPoint(x: r.minX + w * 0.50, y: r.minY + h * 0.12))
        p.addLine(to: CGPoint(x: r.minX + w * 0.84, y: r.minY + h * 0.88))
        // Barra.
        p.move(to: CGPoint(x: r.minX + w * 0.06, y: r.minY + h * 0.60))
        p.addLine(to: CGPoint(x: r.minX + w * 0.94, y: r.minY + h * 0.60))
        return p
    }
}

/// Discos de la barra (dos a cada lado).
struct AtlasPlates: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        for (x, ph) in [(0.10, 0.30), (0.16, 0.22), (0.84, 0.22), (0.90, 0.30)] {
            let rect = CGRect(x: r.minX + w * x - w * 0.025, y: r.minY + h * (0.60 - ph / 2), width: w * 0.05, height: h * ph)
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: w * 0.015, height: w * 0.015))
        }
        return p
    }
}

struct AtlasLogo: View {
    var size: CGFloat = 96
    /// 0…1: cuánto está dibujada la A (para la animación).
    var drawn: CGFloat = 1
    var platesVisible = true

    var body: some View {
        ZStack {
            AtlasMark()
                .trim(from: 0, to: drawn)
                .stroke(DS.brandDiagonal, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
            AtlasPlates()
                .fill(DS.brandDiagonal)
                .opacity(platesVisible ? 1 : 0)
                .scaleEffect(platesVisible ? 1 : 0.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Intro al abrir la app: la A se dibuja, aparecen los discos con un golpe, la palabra ATLAS se abre
/// letra a letra y todo se aleja hacia ti dejando ver la app. Tocar la salta.
struct IntroView: View {
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var plates = false
    @State private var tracking: CGFloat = -6
    @State private var wordOpacity: Double = 0
    @State private var leaving = false
    @State private var done = false

    var body: some View {
        ZStack {
            AtlasBackground()
            VStack(spacing: 22) {
                AtlasLogo(size: 120, drawn: drawn, platesVisible: plates)
                    .shadow(color: DS.indigo.opacity(plates ? 0.7 : 0), radius: 30)
                Text("ATLAS")
                    .font(.display(34, .black))
                    .tracking(tracking)
                    .foregroundStyle(DS.text)
                    .opacity(wordOpacity)
                Text("ENTRENA · COME · PROGRESA")
                    .font(.system(size: 11, weight: .bold).width(.expanded))
                    .tracking(3)
                    .foregroundStyle(DS.text3)
                    .opacity(wordOpacity)
            }
            .scaleEffect(leaving ? 6 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ATLAS")
        .accessibilityIdentifier("intro")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            drawn = 1; plates = true; tracking = 8; wordOpacity = 1
            try? await Task.sleep(for: .milliseconds(900))
            leave(); return
        }
        withAnimation(.easeInOut(duration: 0.7)) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(650))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { plates = true }
        withAnimation(.easeOut(duration: 0.6).delay(0.1)) { tracking = 8; wordOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(1100))
        leave()
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.45)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(460))
            guard !done else { return }
            done = true
            onFinish()
        }
    }
}
