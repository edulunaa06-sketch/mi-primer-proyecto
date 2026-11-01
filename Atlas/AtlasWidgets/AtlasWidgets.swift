import SwiftUI
import WidgetKit

/// Los widgets de Now or Never para la pantalla de inicio y la de bloqueo.
@main
struct AtlasWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoyWidget()
        CaloriasWidget()
    }
}

// MARK: - Color

/// Los mismos colores que la app. Van escritos aquí porque el widget es otro programa y no
/// ve el DesignSystem; son pocos y no cambian a menudo.
enum WColor {
    static let indigo = Color(red: 0.33, green: 0.27, blue: 0.88)
    static let azul = Color(red: 0.05, green: 0.52, blue: 0.72)
    static let tinta = Color(red: 0.055, green: 0.075, blue: 0.137)
    static let tinta2 = Color(red: 0.055, green: 0.075, blue: 0.137).opacity(0.62)
    static let bien = Color(red: 0.06, green: 0.62, blue: 0.38)
    static let ambar = Color(red: 0.78, green: 0.50, blue: 0.02)
    static let mal = Color(red: 0.84, green: 0.16, blue: 0.24)
    static let agua = Color(red: 0.11, green: 0.45, blue: 0.90)

    static func de(_ estado: WidgetEstado) -> Color {
        switch estado {
        case .margen: return indigo
        case .acercandose: return ambar
        case .enObjetivo: return bien
        case .pasado: return mal
        }
    }
}

// MARK: - Datos

struct Entrada: TimelineEntry {
    let date: Date
    let foto: WidgetSnapshot?
}

struct Proveedor: TimelineProvider {
    func placeholder(in context: Context) -> Entrada {
        Entrada(date: Date(), foto: WidgetBridge.ejemplo)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        // En la galería de widgets se enseña el ejemplo; en la pantalla, lo tuyo.
        completion(Entrada(date: Date(), foto: context.isPreview ? WidgetBridge.ejemplo : WidgetBridge.leer()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        let ahora = Date()
        let entrada = Entrada(date: ahora, foto: WidgetBridge.leer())
        // Se vuelve a pedir dentro de 20 minutos. La app además lo refresca al abrirse y al
        // salir, que es cuando de verdad cambian los datos.
        let siguiente = Calendar.current.date(byAdding: .minute, value: 20, to: ahora) ?? ahora
        completion(Timeline(entries: [entrada], policy: .after(siguiente)))
    }
}

// MARK: - Piezas

/// El anillo de calorías, igual que el de la app.
struct Anillo: View {
    let fraccion: Double
    let color: Color
    var grosor: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: grosor)
            Circle()
                .trim(from: 0, to: min(max(fraccion, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private func icono(_ tipo: String) -> String {
    switch tipo {
    case "strength": return "dumbbell.fill"
    case "rest": return "moon.zzz.fill"
    case "run": return "figure.run"
    case "cycling": return "figure.outdoor.cycle"
    case "swimming": return "figure.pool.swim"
    case "football": return "figure.soccer"
    case "basketball": return "figure.basketball"
    case "padel", "tennis": return "figure.tennis"
    case "volleyball": return "figure.volleyball"
    case "mma": return "figure.martial.arts"
    case "boxing": return "figure.boxing"
    case "walking": return "figure.walk"
    case "climbing": return "figure.climbing"
    case "yoga": return "figure.yoga"
    case "rowing": return "figure.rower"
    default: return "figure.mixed.cardio"
    }
}

struct SinDatos: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.circle")
                .font(.title2)
                .foregroundStyle(WColor.indigo)
            Text("Abre Now or Never")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(WColor.tinta2)
        }
    }
}

// MARK: - Widget «Hoy»

struct VistaHoy: View {
    let entrada: Entrada
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let f = entrada.foto {
            let estado = WidgetEstado.de(f.kcalComidas, objetivo: f.kcalObjetivo)
            let color = WColor.de(estado)
            let quedan = f.kcalObjetivo - f.kcalComidas
            let frac = f.kcalObjetivo > 0 ? f.kcalComidas / f.kcalObjetivo : 0

            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Anillo(fraccion: frac, color: color).frame(width: 30, height: 30)
                        Spacer()
                        if f.rachaDias > 0 {
                            Label("\(f.rachaDias)", systemImage: "flame.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WColor.ambar)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(quedan >= 0 ? "Te quedan" : "Te has pasado")
                        .font(.caption2).foregroundStyle(WColor.tinta2)
                    Text("\(Int(abs(quedan).rounded()))")
                        .font(.system(size: 30, weight: .heavy, design: .default))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(color)
                    Text("kcal").font(.caption2.weight(.semibold)).foregroundStyle(color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        Anillo(fraccion: frac, color: color, grosor: 10)
                        VStack(spacing: 0) {
                            Text("\(Int(abs(quedan).rounded()))")
                                .font(.system(size: 20, weight: .heavy))
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text("kcal").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(color)
                    }
                    .frame(width: 74, height: 74)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(estado.texto)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(color)
                            .lineLimit(1)
                        if !f.entrenoNombre.isEmpty {
                            Label {
                                Text(f.entrenoNombre).lineLimit(1)
                            } icon: {
                                Image(systemName: f.entrenoHecho ? "checkmark.circle.fill" : icono(f.entrenoTipo))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(f.entrenoHecho ? WColor.bien : WColor.indigo)
                        }
                        Label {
                            Text("\(f.aguaMl) / \(f.aguaObjetivoMl) ml").lineLimit(1)
                        } icon: {
                            Image(systemName: "drop.fill")
                        }
                        .font(.caption2)
                        .foregroundStyle(WColor.agua)

                        Label {
                            Text("\(Int(f.proteinaG.rounded())) / \(Int(f.proteinaObjetivoG.rounded())) g").lineLimit(1)
                        } icon: {
                            Image(systemName: "fork.knife")
                        }
                        .font(.caption2)
                        .foregroundStyle(WColor.tinta2)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            SinDatos()
        }
    }
}

struct HoyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowOrNeverHoy", provider: Proveedor()) { entrada in
            VistaHoy(entrada: entrada)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Hoy")
        .description("Lo que te queda por comer, el entreno de hoy y el agua.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget de calorías para la pantalla de bloqueo

struct VistaCalorias: View {
    let entrada: Entrada

    var body: some View {
        if let f = entrada.foto {
            let frac = f.kcalObjetivo > 0 ? f.kcalComidas / f.kcalObjetivo : 0
            let quedan = max(0, f.kcalObjetivo - f.kcalComidas)
            Gauge(value: min(max(frac, 0), 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(Int(quedan.rounded()))")
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Gauge(value: 0) {
                Image(systemName: "bolt.fill")
            } currentValueLabel: {
                Text("—")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

struct CaloriasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowOrNeverCalorias", provider: Proveedor()) { entrada in
            VistaCalorias(entrada: entrada)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Calorías")
        .description("Las calorías que te quedan hoy, en la pantalla de bloqueo.")
        .supportedFamilies([.accessoryCircular])
    }
}
