import Foundation

/// Grupos musculares, patrones de movimiento y equipamiento. Es el vocabulario que comparten
/// la biblioteca de ejercicios, el análisis de volumen y las sustituciones.

// MARK: - Grupos musculares

/// Se separan los deltoides (anterior, lateral y posterior) y los músculos de la espalda
/// porque en hipertrofia se entrenan y se cuentan por separado.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Comparable {
    case chest
    case frontDelts
    case sideDelts
    case rearDelts
    case lats
    case upperBack
    case lowerBack
    case traps
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case adductors
    case calves
    case abs
    case obliques

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: return "Pecho"
        case .frontDelts: return "Deltoides anterior"
        case .sideDelts: return "Deltoides lateral"
        case .rearDelts: return "Deltoides posterior"
        case .lats: return "Dorsal"
        case .upperBack: return "Espalda alta"
        case .lowerBack: return "Lumbar"
        case .traps: return "Trapecio"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .forearms: return "Antebrazo"
        case .quads: return "Cuádriceps"
        case .hamstrings: return "Femoral"
        case .glutes: return "Glúteo"
        case .adductors: return "Aductores"
        case .calves: return "Gemelos"
        case .abs: return "Abdomen"
        case .obliques: return "Oblicuos"
        }
    }

    /// Nombre corto para gráficas y etiquetas estrechas.
    var shortLabel: String {
        switch self {
        case .frontDelts: return "Delt. ant."
        case .sideDelts: return "Delt. lat."
        case .rearDelts: return "Delt. post."
        case .upperBack: return "Esp. alta"
        default: return label
        }
    }

    /// Región para agrupar en la interfaz.
    var region: MuscleRegion {
        switch self {
        case .chest, .frontDelts, .sideDelts, .rearDelts, .triceps: return .push
        case .lats, .upperBack, .lowerBack, .traps, .biceps, .forearms: return .pull
        case .quads, .hamstrings, .glutes, .adductors, .calves: return .legs
        case .abs, .obliques: return .core
        }
    }

    /// Orden estable para listas y gráficas (de arriba abajo del cuerpo).
    var sortIndex: Int { MuscleGroup.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: MuscleGroup, rhs: MuscleGroup) -> Bool { lhs.sortIndex < rhs.sortIndex }
}

enum MuscleRegion: String, CaseIterable, Identifiable {
    case push, pull, legs, core
    var id: String { rawValue }
    var label: String {
        switch self {
        case .push: return "Empuje"
        case .pull: return "Tracción"
        case .legs: return "Piernas"
        case .core: return "Core"
        }
    }
}

// MARK: - Patrón de movimiento

/// El patrón sirve para buscar sustitutos razonables: un empuje horizontal se cambia
/// por otro empuje horizontal, no por una apertura.
enum MovementPattern: String, Codable, CaseIterable, Identifiable {
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case squat
    case hinge
    case lunge
    case kneeExtension
    case kneeFlexion
    case hipExtension
    case hipAbduction
    case calfRaise
    case elbowFlexion
    case elbowExtension
    case shoulderAbduction
    case shoulderTransverse
    case pullover
    case coreFlexion
    case coreAntiExtension
    case coreRotation
    case shrug
    case wristFlexion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontalPush: return "Empuje horizontal"
        case .verticalPush: return "Empuje vertical"
        case .horizontalPull: return "Tracción horizontal"
        case .verticalPull: return "Tracción vertical"
        case .squat: return "Sentadilla"
        case .hinge: return "Bisagra de cadera"
        case .lunge: return "Zancada"
        case .kneeExtension: return "Extensión de rodilla"
        case .kneeFlexion: return "Flexión de rodilla"
        case .hipExtension: return "Extensión de cadera"
        case .hipAbduction: return "Abducción de cadera"
        case .calfRaise: return "Elevación de talón"
        case .elbowFlexion: return "Flexión de codo"
        case .elbowExtension: return "Extensión de codo"
        case .shoulderAbduction: return "Abducción de hombro"
        case .shoulderTransverse: return "Apertura / cierre de hombro"
        case .pullover: return "Pullover"
        case .coreFlexion: return "Flexión de tronco"
        case .coreAntiExtension: return "Antiextensión"
        case .coreRotation: return "Rotación de tronco"
        case .shrug: return "Encogimiento"
        case .wristFlexion: return "Flexión de muñeca"
        }
    }
}

// MARK: - Equipamiento

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case machine
    case cable
    case smith
    case bodyweight
    case ezBar
    case kettlebell
    case band
    case plate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: return "Barra"
        case .dumbbell: return "Mancuernas"
        case .machine: return "Máquina"
        case .cable: return "Polea"
        case .smith: return "Multipower"
        case .bodyweight: return "Peso corporal"
        case .ezBar: return "Barra EZ"
        case .kettlebell: return "Kettlebell"
        case .band: return "Goma"
        case .plate: return "Disco"
        }
    }

    var symbol: String {
        switch self {
        case .barbell, .ezBar, .smith: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .machine: return "gearshape.fill"
        case .cable: return "cable.connector"
        case .bodyweight: return "figure.arms.open"
        case .kettlebell: return "figure.kickboxing"
        case .band: return "line.diagonal"
        case .plate: return "circle.circle"
        }
    }

    /// Lo que cambia de verdad entre un material y otro, para explicar una sustitución.
    var trait: String {
        switch self {
        case .barbell: return "Permite más carga total y menos equilibrio por lado."
        case .dumbbell: return "Más recorrido y cada lado trabaja por su cuenta."
        case .machine: return "Trayectoria guiada: más fácil llegar cerca del fallo con seguridad."
        case .cable: return "Tensión constante en todo el recorrido."
        case .smith: return "Guiado como una máquina, con sensación de barra."
        case .bodyweight: return "La carga es tu peso: se progresa con repeticiones o lastre."
        case .ezBar: return "Agarre más cómodo para codos y muñecas."
        case .kettlebell: return "Centro de masa desplazado: exige más al agarre y al core."
        case .band: return "La resistencia aumenta al final del recorrido."
        case .plate: return "Carga sencilla, sin ajuste fino."
        }
    }
}

// MARK: - Referencia de volumen semanal

/// Rango de series semanales por grupo muscular que se suele considerar productivo en hipertrofia.
/// Es una REFERENCIA GENERAL de la literatura de entrenamiento, no una receta: lo que te vale
/// depende de tu recuperación, tu experiencia y tu contexto. La app la usa para avisar de
/// extremos evidentes (0 series en una semana, o un salto muy grande), nunca para diagnosticar.
struct VolumeReference: Equatable {
    let group: MuscleGroup
    /// Por debajo de aquí, es difícil que haya estímulo suficiente para crecer.
    let low: Double
    /// Zona que suele funcionar para la mayoría.
    let typical: ClosedRange<Double>
    /// Por encima de aquí conviene vigilar la recuperación.
    let high: Double

    static let all: [MuscleGroup: VolumeReference] = {
        /// Los grupos grandes aguantan y suelen necesitar más series que los pequeños.
        func make(_ g: MuscleGroup, _ low: Double, _ lo: Double, _ hi: Double, _ high: Double) -> (MuscleGroup, VolumeReference) {
            (g, VolumeReference(group: g, low: low, typical: lo...hi, high: high))
        }
        return Dictionary(uniqueKeysWithValues: [
            make(.chest, 6, 10, 20, 26),
            make(.lats, 6, 10, 20, 26),
            make(.upperBack, 6, 10, 20, 26),
            make(.quads, 6, 10, 20, 26),
            make(.hamstrings, 4, 8, 16, 22),
            make(.glutes, 4, 8, 16, 22),
            make(.frontDelts, 2, 4, 12, 18),
            make(.sideDelts, 4, 8, 20, 26),
            make(.rearDelts, 4, 8, 20, 26),
            make(.biceps, 4, 8, 20, 26),
            make(.triceps, 4, 8, 18, 24),
            make(.calves, 4, 8, 16, 22),
            make(.abs, 2, 6, 16, 22),
            make(.obliques, 0, 2, 10, 16),
            make(.traps, 0, 4, 14, 20),
            make(.lowerBack, 0, 2, 10, 14),
            make(.forearms, 0, 2, 10, 16),
            make(.adductors, 0, 2, 10, 16),
        ])
    }()

    static func reference(for group: MuscleGroup) -> VolumeReference {
        all[group] ?? VolumeReference(group: group, low: 2, typical: 6...16, high: 22)
    }

    /// Dónde cae un número de series dentro de la referencia.
    enum Verdict: String {
        case none, below, inRange, above

        var label: String {
            switch self {
            case .none: return "Sin series"
            case .below: return "Por debajo de la referencia"
            case .inRange: return "En la referencia"
            case .above: return "Por encima de la referencia"
            }
        }
    }

    func verdict(sets: Double) -> Verdict {
        if sets <= 0 { return .none }
        if sets < low { return .below }
        if sets > high { return .above }
        return .inRange
    }
}
