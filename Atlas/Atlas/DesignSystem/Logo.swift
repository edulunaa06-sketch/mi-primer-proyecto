import SwiftUI

/// La marca de Now or Never: la «N» que comparten NOW y NEVER.
///
/// Un monograma macizo y geométrico, sin adornos: a 60 puntos en la pantalla de inicio, una
/// letra rellena se reconoce y un dibujo con detalles se convierte en una mancha. El mismo
/// trazo que el icono de la app (`tools/gen_appicon.py`).
struct BrandMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        }
        // Contorno de la N: pata izquierda, diagonal bajando, pata derecha, y de vuelta por abajo.
        // La diagonal tiene el mismo grosor perpendicular que las patas (0,155 de ancho), que en
        // vertical son 0,169 por la inclinación. Si no, la letra se ve coja.
        p.move(to: pt(0.200, 0.060))
        p.addLine(to: pt(0.355, 0.060))
        p.addLine(to: pt(0.645, 0.551))
        p.addLine(to: pt(0.645, 0.060))
        p.addLine(to: pt(0.800, 0.060))
        p.addLine(to: pt(0.800, 0.720))
        p.addLine(to: pt(0.645, 0.720))
        p.addLine(to: pt(0.355, 0.229))
        p.addLine(to: pt(0.355, 0.720))
        p.addLine(to: pt(0.200, 0.720))
        p.closeSubpath()
        return p
    }
}

/// El filo de oro de debajo del monograma: la línea que llevan los logotipos de las marcas caras.
struct BrandRule: Shape {
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX + r.width * 0.20, y: r.minY + r.height * 0.845,
                    width: r.width * 0.60, height: max(1, r.height * 0.018)))
    }
}

/// El monograma en oro, con la luz cruzándolo.
struct BrandLogo: View {
    var size: CGFloat = 96
    /// 0…1: cuánto ha subido el oro dentro de la letra (la entrada la va llenando).
    var drawn: CGFloat = 1
    /// 0…1: cuánto se ha abierto el filo de debajo, desde el centro.
    var ruleOpen: CGFloat = 1
    /// Dónde está el brillo que cruza el metal: −1 fuera por la izquierda, 1 fuera por la derecha.
    var shine: CGFloat = 1

    var body: some View {
        ZStack {
            // El oro de la letra, con la luz encima. El brillo va en un `overlay` y no como
            // hermano en el ZStack: así no puede cambiar el tamaño de la letra al crecer.
            BrandMark()
                .fill(DS.brandDiagonal)
                .frame(width: size, height: size)
                .overlay {
                    // La banda de luz: inclinada y recortada por la propia letra, así parece un
                    // reflejo sobre metal y no un rectángulo pasando por encima.
                    LinearGradient(colors: [.clear, DS.champagne.opacity(0.95), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: size * 0.26, height: size * 1.8)
                        .rotationEffect(.degrees(18))
                        .offset(x: shine * size * 0.95)
                }
                .mask { BrandMark().frame(width: size, height: size) }
                .mask(alignment: .bottom) { Rectangle().frame(height: size * clamped(drawn)) }

            BrandRule()
                .fill(DS.brandDiagonal)
                .frame(width: size, height: size)
                .scaleEffect(x: clamped(ruleOpen), y: 1, anchor: .center)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Las animaciones con muelle se pasan de 1 y bajan de 0; recortarlas evita que la letra
    /// se dibuje de más o que el filo se gire del revés.
    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// Telón de entrada: el oro llena la N, el filo se abre, la luz la cruza, NOW baja desde arriba
/// y NEVER sube desde abajo, OR aparece enfocándose en medio, NOW se enciende y NEVER se apaga
/// (eliges ahora), y el telón se abre por la mitad dejando ver la app. Tocar la pantalla lo salta.
struct IntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// El oro llenando la letra, de abajo a arriba.
    @State private var drawn: CGFloat = 0
    /// El filo de debajo abriéndose desde el centro.
    @State private var ruleOpen: CGFloat = 0
    /// La luz cruzando el monograma.
    @State private var shine: CGFloat = -1.2
    /// NOW y NEVER ya han entrado en su sitio.
    @State private var wordsIn = false
    /// El OR del medio está enfocado.
    @State private var orIn = false
    /// NOW encendido en oro, NEVER apagado.
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
                        BrandLogo(size: 112, drawn: drawn, ruleOpen: ruleOpen, shine: shine)
                            .shadow(color: DS.gold.opacity(ruleOpen > 0 ? 0.45 : 0), radius: 34)
                        Text("NOW")
                            .font(.display(46, .black))
                            .tracking(6)
                            .foregroundStyle(chosen ? AnyShapeStyle(DS.brandDiagonal) : AnyShapeStyle(DS.text))
                            .shadow(color: DS.gold.opacity(chosen ? 0.45 : 0), radius: 22)
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
                            .opacity(wordsIn ? (chosen ? 0.20 : 1) : 0)
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
                    .foregroundStyle(DS.gold)
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
            AtlasBackdrop()
                .frame(width: total.width, height: total.height)
                .frame(height: total.height / 2, alignment: isTop ? .top : .bottom)
                .clipped()
            content()
        }
        .frame(width: total.width, height: total.height / 2)
        .clipped()
    }

    private func play() async {
        if reduceMotion {
            drawn = 1; ruleOpen = 1; shine = 1.2; wordsIn = true; orIn = true; chosen = true
            try? await Task.sleep(for: .milliseconds(1000))
            leave(); return
        }
        withAnimation(.easeInOut(duration: 0.6)) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(560))
        DS.haptic(.heavy)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) { ruleOpen = 1 }
        withAnimation(.easeInOut(duration: 0.75).delay(0.1)) { shine = 1.2 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(0.12)) { wordsIn = true }
        try? await Task.sleep(for: .milliseconds(560))
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
