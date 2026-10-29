import Foundation

/// Dibujo del cuerpo por músculos: de frente y de espalda.
///
/// Las coordenadas van de 0 a 1 (0,0 arriba a la izquierda) sobre un lienzo con forma de
/// persona (más alto que ancho). Casi todo se describe SOLO de un lado y se refleja, así que
/// el cuerpo sale simétrico y hay la mitad de números que mantener.
///
/// Es un esquema para entender de un vistazo qué trabajas, no una lámina de anatomía.
enum BodyMap {
    /// Proporción ancho : alto del lienzo.
    static let aspect: Double = 1.0 / 2.15

    struct Point: Equatable {
        let x: Double
        let y: Double
        init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    /// Una pieza del dibujo: o un músculo, o un trozo de silueta.
    struct Piece: Equatable, Identifiable {
        /// nil = silueta (cuerpo, cabeza, manos…): no es un músculo y no se colorea.
        let group: MuscleGroup?
        let points: [Point]
        /// Se dibuja también reflejada en el otro lado del cuerpo.
        let mirrored: Bool
        /// Para identificar cada trozo en la lista.
        let name: String

        var id: String { name }

        init(_ name: String, _ group: MuscleGroup?, mirrored: Bool = true, _ points: [(Double, Double)]) {
            self.name = name
            self.group = group
            self.mirrored = mirrored
            self.points = points.map { Point($0.0, $0.1) }
        }

        /// La misma pieza reflejada respecto al eje del cuerpo.
        var reflected: Piece {
            Piece(name + "-izq", group, mirrored: false, points.map { (1 - $0.x, $0.y) })
        }
    }

    enum Side: String, CaseIterable, Identifiable {
        case front, back
        var id: String { rawValue }
        var label: String { self == .front ? "De frente" : "De espalda" }
        var other: Side { self == .front ? .back : .front }
    }

    // MARK: Silueta

    /// Cabeza, cuello, tronco, brazos y piernas. Es el contorno sobre el que van los músculos.
    static let silhouette: [Piece] = [
        Piece("cabeza", nil, mirrored: false, [
            (0.500, 0.010), (0.536, 0.017), (0.560, 0.038), (0.567, 0.066),
            (0.560, 0.094), (0.536, 0.115), (0.500, 0.122), (0.464, 0.115),
            (0.440, 0.094), (0.433, 0.066), (0.440, 0.038), (0.464, 0.017),
        ]),
        Piece("cuello", nil, mirrored: false, [
            (0.463, 0.112), (0.537, 0.112), (0.545, 0.160), (0.455, 0.160),
        ]),
        Piece("tronco", nil, [
            (0.500, 0.142), (0.618, 0.158), (0.672, 0.212), (0.648, 0.300),
            (0.616, 0.395), (0.652, 0.455), (0.648, 0.498), (0.500, 0.502),
        ]),
        Piece("brazo", nil, [
            (0.640, 0.185), (0.700, 0.215), (0.722, 0.330), (0.742, 0.450),
            (0.748, 0.510), (0.712, 0.520), (0.690, 0.455), (0.668, 0.335),
            (0.630, 0.245),
        ]),
        Piece("pierna", nil, [
            (0.505, 0.470), (0.648, 0.468), (0.628, 0.600), (0.608, 0.690),
            (0.598, 0.790), (0.592, 0.880), (0.600, 0.930), (0.522, 0.932),
            (0.520, 0.860), (0.512, 0.700), (0.505, 0.600),
        ]),
    ]

    // MARK: De frente

    static let front: [Piece] = [
        Piece("trapecio-frontal", .traps, [
            (0.500, 0.128), (0.622, 0.168), (0.572, 0.192), (0.500, 0.178),
        ]),
        Piece("deltoides-anterior", .frontDelts, [
            (0.610, 0.172), (0.660, 0.192), (0.668, 0.244), (0.634, 0.250), (0.604, 0.206),
        ]),
        Piece("deltoides-lateral-frontal", .sideDelts, [
            (0.658, 0.186), (0.692, 0.212), (0.696, 0.256), (0.666, 0.250), (0.660, 0.212),
        ]),
        Piece("pecho", .chest, [
            (0.504, 0.186), (0.600, 0.192), (0.644, 0.232), (0.628, 0.282), (0.504, 0.288),
        ]),
        Piece("biceps", .biceps, [
            (0.652, 0.262), (0.700, 0.268), (0.706, 0.340), (0.662, 0.348),
        ]),
        Piece("antebrazo-frontal", .forearms, [
            (0.668, 0.360), (0.712, 0.356), (0.730, 0.456), (0.692, 0.464),
        ]),
        Piece("abdomen", .abs, mirrored: false, [
            (0.444, 0.300), (0.556, 0.300), (0.560, 0.400), (0.500, 0.440), (0.440, 0.400),
        ]),
        Piece("oblicuos", .obliques, [
            (0.562, 0.302), (0.612, 0.312), (0.598, 0.398), (0.562, 0.404),
        ]),
        Piece("cuadriceps", .quads, [
            (0.516, 0.485), (0.602, 0.480), (0.616, 0.590), (0.572, 0.672), (0.528, 0.668),
        ]),
        Piece("aductores", .adductors, [
            (0.504, 0.482), (0.552, 0.488), (0.544, 0.588), (0.504, 0.600),
        ]),
        Piece("gemelos-frontal", .calves, [
            (0.532, 0.712), (0.588, 0.706), (0.582, 0.820), (0.542, 0.836),
        ]),
    ]

    // MARK: De espalda

    static let back: [Piece] = [
        Piece("trapecio", .traps, [
            (0.500, 0.126), (0.638, 0.174), (0.572, 0.232), (0.500, 0.268),
        ]),
        Piece("deltoides-posterior", .rearDelts, [
            (0.624, 0.174), (0.668, 0.196), (0.674, 0.244), (0.642, 0.250), (0.616, 0.208),
        ]),
        Piece("deltoides-lateral-trasero", .sideDelts, [
            (0.666, 0.190), (0.698, 0.216), (0.700, 0.256), (0.672, 0.250), (0.668, 0.216),
        ]),
        Piece("espalda-alta", .upperBack, [
            (0.574, 0.198), (0.650, 0.226), (0.644, 0.272), (0.560, 0.250),
        ]),
        Piece("dorsal", .lats, [
            (0.504, 0.272), (0.560, 0.256), (0.646, 0.280), (0.628, 0.356),
            (0.570, 0.404), (0.504, 0.396),
        ]),
        Piece("lumbar", .lowerBack, mirrored: false, [
            (0.456, 0.386), (0.544, 0.386), (0.556, 0.436), (0.444, 0.436),
        ]),
        Piece("triceps", .triceps, [
            (0.652, 0.262), (0.702, 0.268), (0.708, 0.342), (0.662, 0.348),
        ]),
        Piece("antebrazo-trasero", .forearms, [
            (0.668, 0.360), (0.714, 0.356), (0.732, 0.456), (0.694, 0.464),
        ]),
        Piece("gluteo", .glutes, [
            (0.504, 0.440), (0.602, 0.436), (0.620, 0.508), (0.566, 0.536), (0.504, 0.532),
        ]),
        Piece("femoral", .hamstrings, [
            (0.516, 0.546), (0.606, 0.540), (0.602, 0.656), (0.530, 0.668),
        ]),
        Piece("gemelos", .calves, [
            (0.532, 0.700), (0.592, 0.694), (0.586, 0.812), (0.542, 0.830),
        ]),
    ]

    /// Todas las piezas de un lado del cuerpo, ya con las reflejadas.
    static func pieces(_ side: Side) -> [Piece] {
        expand(side == .front ? front : back)
    }

    static var silhouettePieces: [Piece] { expand(silhouette) }

    private static func expand(_ pieces: [Piece]) -> [Piece] {
        pieces.flatMap { $0.mirrored ? [$0, $0.reflected] : [$0] }
    }

    /// Músculos que se ven en cada lado del cuerpo (para decir cuáles hay que mirar en el otro).
    static func visibleMuscles(_ side: Side) -> [MuscleGroup] {
        let groups = (side == .front ? front : back).compactMap(\.group)
        var seen: Set<MuscleGroup> = []
        return groups.filter { seen.insert($0).inserted }.sorted()
    }

    /// Los músculos que no se dibujan en ningún lado (por si algún día falta alguno).
    static var notDrawn: [MuscleGroup] {
        let drawn = Set(visibleMuscles(.front) + visibleMuscles(.back))
        return MuscleGroup.allCases.filter { !drawn.contains($0) }
    }
}
