import Foundation

/// Ejercicios que crea el usuario cuando la biblioteca no trae el suyo.
///
/// La clave está en el NOMBRE: el catálogo ya busca por nombre cuando no reconoce el identificador,
/// así que en cuanto creas «Jalón al pecho enfatizando espalda alta» con su músculo, todo lo que
/// ya tenías apuntado con ese nombre empieza a contar en el volumen de ese músculo. Si luego lo
/// renombras, el nombre anterior se guarda como alias para no perder lo registrado.
enum CustomExerciseRules {
    /// Lo máximo que se admite como nombre (cabe en una línea de la rutina).
    static let maxNameLength = 60

    enum Problem: Equatable {
        case empty
        case tooLong
        case alreadyInLibrary(String)
        case alreadyYours(String)

        var message: String {
            switch self {
            case .empty: return "Ponle un nombre al ejercicio."
            case .tooLong: return "El nombre es demasiado largo (máximo \(maxNameLength) caracteres)."
            case .alreadyInLibrary(let name): return "«\(name)» ya está en la biblioteca: úsalo desde ahí."
            case .alreadyYours(let name): return "Ya tienes un ejercicio tuyo llamado «\(name)»."
            }
        }
    }

    /// Comprueba el nombre antes de guardar. `editingID` es el ejercicio que se está editando
    /// (para que no choque consigo mismo).
    static func validate(name: String, mine: [(id: String, name: String)], editingID: String? = nil,
                         libraryLookup: (String) -> Bool = { ExerciseCatalog.info(named: $0) != nil }) -> Problem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxNameLength { return .tooLong }
        if libraryLookup(trimmed) { return .alreadyInLibrary(trimmed) }
        let normalized = ExerciseCatalog.normalize(trimmed)
        if let clash = mine.first(where: { ExerciseCatalog.normalize($0.name) == normalized && $0.id != editingID }) {
            return .alreadyYours(clash.name)
        }
        return nil
    }

    /// Patrón de movimiento típico de cada músculo, para no obligar a elegirlo.
    /// Es un punto de partida: el usuario puede cambiarlo.
    static func suggestedPattern(for muscle: MuscleGroup) -> MovementPattern {
        switch muscle {
        case .chest: return .horizontalPush
        case .frontDelts: return .verticalPush
        case .sideDelts: return .shoulderAbduction
        case .rearDelts: return .shoulderTransverse
        case .lats: return .verticalPull
        case .upperBack: return .horizontalPull
        case .lowerBack, .hamstrings, .glutes: return .hinge
        case .traps: return .shrug
        case .biceps: return .elbowFlexion
        case .triceps: return .elbowExtension
        case .forearms: return .wristFlexion
        case .quads: return .squat
        case .adductors: return .hipAbduction
        case .calves: return .calfRaise
        case .abs: return .coreFlexion
        case .obliques: return .coreRotation
        }
    }

    /// Ficha de biblioteca a partir de lo que ha rellenado el usuario.
    static func info(id: String, name: String, primary: MuscleGroup, secondary: [MuscleGroup],
                     pattern: MovementPattern, equipment: Equipment, unilateral: Bool,
                     sets: Int, repMin: Int, repMax: Int, note: String, aliases: [String]) -> ExerciseInfo {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExerciseInfo(
            id, name.trimmingCharacters(in: .whitespacesAndNewlines),
            primary: primary,
            secondary: secondary.filter { $0 != primary },
            pattern: pattern, equipment: equipment, unilateral: unilateral,
            sets: max(1, sets), reps: max(1, repMin)...max(max(1, repMin), repMax),
            aliases: aliases,
            execution: clean.isEmpty ? [] : [clean],
            mistakes: [],
            safety: nil,
            trait: "Ejercicio tuyo: los músculos los has elegido tú, así que el volumen se reparte como le hayas dicho.",
            isCustom: true
        )
    }
}

// MARK: - Los ejercicios del usuario dentro del catálogo

extension ExerciseCatalog {
    /// Los ejercicios del usuario, cargados de la base de datos. Se consultan igual que los de la
    /// biblioteca, así que cuentan en el volumen por músculo, en los informes y en las sustituciones.
    private static let customLock = NSLock()
    private static var customStore: [ExerciseInfo] = []
    private static var customByID: [String: ExerciseInfo] = [:]
    private static var customByName: [String: ExerciseInfo] = [:]

    /// Reemplaza la lista de ejercicios del usuario (al abrir la app y cada vez que se cambia uno).
    static func useCustom(_ infos: [ExerciseInfo]) {
        var byID: [String: ExerciseInfo] = [:]
        var byName: [String: ExerciseInfo] = [:]
        for info in infos {
            byID[info.id] = info
            byName[normalize(info.name)] = info
            // Los nombres anteriores siguen apuntando aquí: lo registrado antes de renombrarlo no se pierde.
            for alias in info.aliases where byName[normalize(alias)] == nil {
                byName[normalize(alias)] = info
            }
        }
        customLock.lock()
        customStore = infos
        customByID = byID
        customByName = byName
        customLock.unlock()
    }

    static var customExercises: [ExerciseInfo] {
        customLock.lock()
        defer { customLock.unlock() }
        return customStore
    }

    /// Ficha de un ejercicio del usuario, por identificador o por nombre.
    static func custom(id: String?, name: String?) -> ExerciseInfo? {
        customLock.lock()
        defer { customLock.unlock() }
        if let id, let match = customByID[id] { return match }
        if let name, let match = customByName[normalize(name)] { return match }
        return nil
    }

    /// Solo para las pruebas: deja el catálogo sin ejercicios del usuario.
    static func clearCustom() { useCustom([]) }
}
