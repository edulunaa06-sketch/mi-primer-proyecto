import SwiftUI

/// El rayo de Now or Never.
///
/// Macizo y con las puntas achaflanadas en vez de en aguja: a 20 puntos en una cabecera, una
/// punta afilada se queda en nada y el rayo deja de leerse. El mismo trazo que el icono de la
/// app (`tools/gen_appicon.py`).
struct BrandBolt: Shape {
    /// Lo que ocupa el rayo dentro del cuadro. El resto lo ocupa el aro.
    var scale: CGFloat = 0.58

    /// El rayo en coordenadas 0…1, de la punta de arriba a la de abajo.
    static let points: [(CGFloat, CGFloat)] = [
        (0.566, 0.070),  // punta de arriba, lado izquierdo del chaflán
        (0.662, 0.070),  // punta de arriba, lado derecho
        (0.548, 0.432),  // baja por el canto derecho del brazo de arriba
        (0.742, 0.432),  // el escalón de la derecha
        (0.430, 0.930),  // punta de abajo, lado derecho
        (0.336, 0.930),  // punta de abajo, lado izquierdo
        (0.452, 0.568),  // sube por el canto izquierdo del brazo de abajo
        (0.258, 0.568),  // el escalón de la izquierda
    ]

    func path(in r: CGRect) -> Path {
        let xs = Self.points.map(\.0), ys = Self.points.map(\.1)
        // Se centra por su caja, no por el 0,5: el rayo está inclinado y, sin esto, queda
        // descolgado dentro del aro.
        let bx = (xs.min()! + xs.max()!) / 2, by = (ys.min()! + ys.max()!) / 2
        var p = Path()
        for (i, point) in Self.points.enumerated() {
            let pt = CGPoint(x: r.midX + (point.0 - bx) * scale * r.width,
                             y: r.midY + (point.1 - by) * scale * r.height)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// El aro que rodea al rayo, abierto por arriba.
///
/// Abierto y no cerrado a propósito: un círculo cerrado se queda quieto, y este, con el hueco,
/// parece que está dando la vuelta. Además es lo que permite dibujarlo de un trazo en la entrada.
struct BrandRing: Shape {
    /// Grados de hueco, centrados arriba.
    var gap: CGFloat = 62

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY),
                 radius: min(r.width, r.height) * 0.415,
                 startAngle: .degrees(-90 + gap / 2),
                 endAngle: .degrees(270 - gap / 2),
                 clockwise: false)
        return p
    }
}

/// La marca entera: el rayo dentro del aro, en el azul de Now or Never.
struct BrandLogo: View {
    var size: CGFloat = 96
    /// 0…1: cuánto aro se ha dibujado (la entrada lo va trazando).
    var drawn: CGFloat = 1
    /// 0…1: cuánto ha entrado el rayo (la entrada lo deja caer dentro).
    var strike: CGFloat = 1

    var body: some View {
        ZStack {
            BrandRing()
                .trim(from: 0, to: clamped(drawn))
                .stroke(DS.brandDiagonal,
                        style: StrokeStyle(lineWidth: size * 0.058, lineCap: .round))
            BrandBolt()
                .fill(DS.brandDiagonal)
                // Entra un pelín grande y se asienta: así parece que cae, no que aparece.
                .scaleEffect(0.72 + 0.28 * clamped(strike))
                .opacity(Double(clamped(strike)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Las animaciones con muelle se pasan de 1 y bajan de 0; recortarlas evita que el aro
    /// se dibuje de más o que el rayo se dé la vuelta.
    private func clamped(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
}

/// La entrada al abrir la app: el aro se traza de una vuelta, el rayo cae dentro con un golpe,
/// el nombre se abre letra a letra y todo se va con un respiro dejando ver la app.
/// Tocar la pantalla la salta.
struct IntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// El aro trazándose.
    @State private var drawn: CGFloat = 0
    /// El rayo cayendo dentro.
    @State private var strike: CGFloat = 0
    /// El destello del momento del golpe.
    @State private var flash: Double = 0
    /// Separación entre las letras del nombre: empiezan apretadas y se abren.
    @State private var tracking: CGFloat = -3
    @State private var wordIn = false
    /// El lema de abajo.
    @State private var taglineIn = false
    /// Todo se va.
    @State private var leaving = false
    @State private var done = false

    var body: some View {
        ZStack {
            AtlasBackdrop().ignoresSafeArea()

            VStack(spacing: 24) {
                BrandLogo(size: 128, drawn: drawn, strike: strike)
                    // El resplandor solo existe en el instante del golpe.
                    .shadow(color: DS.indigo.opacity(flash * 0.55), radius: 40)
                    .overlay {
                        Circle()
                            .fill(DS.sky.opacity(flash * 0.35))
                            .frame(width: 128, height: 128)
                            .blur(radius: 30)
                            .allowsHitTesting(false)
                    }

                VStack(spacing: 10) {
                    Text("NOW OR NEVER")
                        .font(.display(26, .black))
                        .tracking(tracking)
                        .foregroundStyle(DS.text)
                        .opacity(wordIn ? 1 : 0)
                    Text("ENTRENA · COME · PROGRESA")
                        .font(.system(size: 11, weight: .bold).width(.expanded))
                        .tracking(3)
                        .foregroundStyle(DS.text3)
                        .opacity(taglineIn ? 1 : 0)
                }
            }
            // Al irse se acerca un punto, como si la app estuviera debajo.
            .scaleEffect(leaving ? 1.12 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { leave() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now or Never")
        .accessibilityIdentifier("intro")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            drawn = 1; strike = 1; tracking = 4; wordIn = true; taglineIn = true
            try? await Task.sleep(for: .milliseconds(900))
            leave(); return
        }
        // El aro da la vuelta.
        withAnimation(.easeInOut(duration: 0.62)) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(540))
        // El rayo cae dentro, con golpe y destello.
        DS.haptic(.heavy)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) { strike = 1 }
        withAnimation(.easeOut(duration: 0.12)) { flash = 1 }
        withAnimation(.easeOut(duration: 0.55).delay(0.12)) { flash = 0 }
        // El nombre se abre.
        withAnimation(.easeOut(duration: 0.55).delay(0.14)) { tracking = 4; wordIn = true }
        try? await Task.sleep(for: .milliseconds(520))
        withAnimation(.easeOut(duration: 0.35)) { taglineIn = true }
        // Para las capturas del CI la entrada se queda aquí, con todo en su sitio.
        if RootView.screenshotSplash { return }
        try? await Task.sleep(for: .milliseconds(680))
        leave()
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.42)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !done else { return }
            done = true
            onFinish()
        }
    }
}
