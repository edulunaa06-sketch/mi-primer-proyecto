import SwiftUI

/// Marca de Now or Never: la «N» que comparten NOW y NEVER, atravesada por una barra olímpica
/// con sus discos. El mismo trazo que el icono de la app (`tools/gen_appicon.py`).
struct BrandMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + w * x, y: r.minY + h * y) }
        // La N: sube la primera pata, baja la diagonal y sube la segunda, de un solo trazo
        // (así la animación la dibuja como se escribe a mano).
        p.move(to: pt(0.27, 0.62))
        p.addLine(to: pt(0.27, 0.14))
        p.addLine(to: pt(0.73, 0.62))
        p.addLine(to: pt(0.73, 0.14))
        // La barra, debajo de la N, con sus discos a los lados.
        p.move(to: pt(0.10, 0.80))
        p.addLine(to: pt(0.90, 0.80))
        return p
    }
}

/// Discos de la barra: dos a cada lado, el de fuera más grande.
struct BrandPlates: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        for (x, ph) in [(0.14, 0.24), (0.20, 0.17), (0.80, 0.17), (0.86, 0.24)] {
            let rect = CGRect(x: r.minX + w * x - w * 0.0225, y: r.minY + h * (0.80 - ph / 2),
                              width: w * 0.045, height: h * ph)
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: w * 0.014, height: w * 0.014))
        }
        return p
    }
}

struct BrandLogo: View {
    var size: CGFloat = 96
    /// 0…1: cuánto está dibujada la N (para la animación de entrada).
    var drawn: CGFloat = 1
    var platesVisible = true

    var body: some View {
        ZStack {
            BrandMark()
                .trim(from: 0, to: drawn)
                .stroke(DS.brandDiagonal, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
            BrandPlates()
                .fill(DS.brandDiagonal)
                .opacity(platesVisible ? 1 : 0)
                .scaleEffect(platesVisible ? 1 : 0.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Telón de entrada: se dibuja la marca, NOW baja desde arriba y NEVER sube desde abajo,
/// OR aparece enfocándose en medio, NOW se enciende y NEVER se apaga (eliges ahora),
/// y el telón se abre por la mitad dejando ver la app. Tocar la pantalla lo salta.
struct IntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var plates = false
    /// NOW y NEVER ya han entrado en su sitio.
    @State private var wordsIn = false
    /// El OR del medio está enfocado.
    @State private var orIn = false
    /// NOW encendido con el degradado de la marca, NEVER apagado.
    @State private var chosen = false
    /// Las dos mitades del telón se separan.
    @State private var opened = false
    @State private var done = false

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.height / 2 + 40
            ZStack {
                // Mitad de arriba: la marca y NOW.
                curtainHalf(total: geo.size, isTop: true) {
                    VStack(spacing: 18) {
                        BrandLogo(size: 104, drawn: drawn, platesVisible: plates)
                            .shadow(color: DS.indigo.opacity(plates ? 0.7 : 0), radius: 30)
                        Text("NOW")
                            .font(.display(46, .black))
                            .tracking(6)
                            .foregroundStyle(chosen ? AnyShapeStyle(DS.brandDiagonal) : AnyShapeStyle(DS.text))
                            .shadow(color: DS.cyan.opacity(chosen ? 0.55 : 0), radius: 22)
                            .offset(y: wordsIn ? 0 : -70)
                            .opacity(wordsIn ? 1 : 0)
                    }
                    .padding(.bottom, 26)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: opened ? -travel : 0)

                // Mitad de abajo: NEVER y el lema.
                curtainHalf(total: geo.size, isTop: false) {
                    VStack(spacing: 14) {
                        Text("NEVER")
                            .font(.display(46, .black))
                            .tracking(6)
                            .foregroundStyle(DS.text)
                            .opacity(wordsIn ? (chosen ? 0.22 : 1) : 0)
                            .offset(y: wordsIn ? 0 : 70)
                        Text("ENTRENA · COME · PROGRESA")
                            .font(.system(size: 11, weight: .bold).width(.expanded))
                            .tracking(3)
                            .foregroundStyle(DS.text3)
                            .opacity(orIn ? 1 : 0)
                    }
                    .padding(.top, 26)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: opened ? travel : 0)

                // El OR va justo en la línea por la que se parte el telón.
                Text("OR")
                    .font(.system(size: 15, weight: .black).width(.expanded))
                    .tracking(8)
                    .foregroundStyle(DS.cyan)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(DS.bg).overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1)))
                    .blur(radius: orIn ? 0 : 12)
                    .scaleEffect(orIn ? 1 : 1.6)
                    .opacity(orIn && !opened ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now or Never")
        .accessibilityIdentifier("intro")
        .task { await play() }
    }

    /// Una mitad del telón: su trozo del fondo (para que las dos juntas se vean como una sola
    /// pantalla, sin costura) y su contenido pegado a la línea por la que se abre.
    private func curtainHalf<Content: View>(total: CGSize, isTop: Bool,
                                            @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: isTop ? .bottom : .top) {
            backdrop
                .frame(width: total.width, height: total.height)
                .frame(height: total.height / 2, alignment: isTop ? .top : .bottom)
                .clipped()
            content()
        }
        .frame(width: total.width, height: total.height / 2)
        .clipped()
    }

    /// El mismo fondo de la app, pero sin `ignoresSafeArea` para poder cortarlo por la mitad.
    private var backdrop: some View {
        ZStack {
            DS.bg
            RadialGradient(colors: [DS.indigo.opacity(0.28), .clear], center: .init(x: 0.15, y: -0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [DS.cyan.opacity(0.10), .clear], center: .init(x: 1.0, y: 1.0), startRadius: 0, endRadius: 380)
        }
    }

    private func play() async {
        if reduceMotion {
            drawn = 1; plates = true; wordsIn = true; orIn = true; chosen = true
            try? await Task.sleep(for: .milliseconds(1000))
            leave(); return
        }
        withAnimation(.easeInOut(duration: 0.55)) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        DS.haptic(.heavy)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { plates = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.12)) { wordsIn = true }
        try? await Task.sleep(for: .milliseconds(520))
        withAnimation(.easeOut(duration: 0.4)) { orIn = true }
        try? await Task.sleep(for: .milliseconds(420))
        DS.haptic(.rigid)
        withAnimation(.easeInOut(duration: 0.5)) { chosen = true }
        // Para las capturas del CI la entrada se queda aquí, con todo en su sitio.
        if RootView.screenshotSplash { return }
        try? await Task.sleep(for: .milliseconds(620))
        leave()
    }

    private func leave() {
        guard !opened else { return }
        withAnimation(.easeInOut(duration: 0.5)) { opened = true }
        Task {
            try? await Task.sleep(for: .milliseconds(480))
            guard !done else { return }
            done = true
            onFinish()
        }
    }
}
