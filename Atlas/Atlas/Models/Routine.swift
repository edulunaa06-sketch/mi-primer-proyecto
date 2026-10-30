import Foundation

/// Rutina semanal fija definida por el usuario.
/// IMPORTANTE: no modificar ejercicios, orden, series ni rangos sin autorización del usuario.

enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case strength
    case run
    case rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength: return "Fuerza"
        case .run: return "Carrera"
        case .rest: return "Descanso"
        }
    }

    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .rest: return "moon.zzz.fill"
        }
    }
}

struct ExerciseDefinition: Identifiable, Hashable {
    /// Identificador estable (se usa para guardar historial). No cambiar.
    let id: String
    let name: String
    let sets: Int
    let repRange: String

    var prescription: String { "\(sets) × \(repRange)" }

    /// "6–10" (o "6-10") → (6, 10). Un único número ("12") → (12, 12).
    static func parseRange(_ text: String) -> (min: Int, max: Int)? {
        let parts = text.split(whereSeparator: { $0 == "–" || $0 == "-" || $0 == "—" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, let lo = numbers.first, let hi = numbers.last,
              (1...2).contains(numbers.count), lo > 0, hi >= lo else { return nil }
        return (lo, hi)
    }

    static func formatRange(min: Int, max: Int) -> String {
        min == max ? "\(min)" : "\(min)–\(max)"
    }
}

struct SessionDefinition: Identifiable, Hashable {
    /// Identificador estable (se usa como clave de historial). No cambiar.
    let id: String
    let title: String
    let kind: SessionKind
    /// 1 = lunes … 7 = domingo
    let weekday: Int
    let detail: String
    let exercises: [ExerciseDefinition]

    /// Misma sesión con la lista de ejercicios personalizada por el usuario.
    func with(exercises custom: [ExerciseDefinition]) -> SessionDefinition {
        SessionDefinition(id: id, title: title, kind: kind, weekday: weekday, detail: detail, exercises: custom)
    }

    /// Misma sesión convertida en otro tipo de día (fuerza, carrera o descanso).
    ///
    /// Se vacía el `detail`: describe el día original («Corre entre 25 y 35 minutos»), y dejarlo
    /// en un día que has pasado a fuerza sería mentir al que lo lee.
    func with(kind custom: SessionKind?) -> SessionDefinition {
        guard let custom, custom != kind else { return self }
        return SessionDefinition(id: id, title: title, kind: custom, weekday: weekday,
                                 detail: "", exercises: custom == .strength ? exercises : [])
    }

    /// Misma sesión con el nombre que le ha puesto el usuario (vacío = nombre original).
    func with(title custom: String?) -> SessionDefinition {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return self }
        return SessionDefinition(id: id, title: String(trimmed.prefix(40)), kind: kind, weekday: weekday, detail: detail, exercises: exercises)
    }
}

enum WeeklyRoutine {
    static let mondayRun = SessionDefinition(
        id: "mon-run",
        title: "Carrera suave",
        kind: .run,
        weekday: 1,
        detail: "Correr entre 25 y 35 minutos a ritmo fácil.",
        exercises: []
    )

    static let tuesdayPushA = SessionDefinition(
        id: "tue-push-a",
        title: "Push A",
        kind: .strength,
        weekday: 2,
        detail: "Pecho, hombro y tríceps.",
        exercises: [
            ExerciseDefinition(id: "tue-bench-barbell", name: "Press de banca con barra", sets: 3, repRange: "6–10"),
            ExerciseDefinition(id: "tue-incline-db-press", name: "Press inclinado con mancuernas", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "tue-machine-shoulder-press", name: "Press de hombros en máquina", sets: 2, repRange: "8–12"),
            ExerciseDefinition(id: "tue-cable-lateral-raise", name: "Elevaciones laterales en polea", sets: 3, repRange: "12–20"),
            ExerciseDefinition(id: "tue-overhead-triceps-ext", name: "Extensión de tríceps por encima de la cabeza", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "tue-rope-triceps-ext", name: "Extensión de tríceps con cuerda", sets: 2, repRange: "10–15"),
        ]
    )

    static let wednesdayPullA = SessionDefinition(
        id: "wed-pull-a",
        title: "Pull A",
        kind: .strength,
        weekday: 3,
        detail: "Espalda, deltoide posterior y bíceps.",
        exercises: [
            ExerciseDefinition(id: "wed-neutral-lat-pulldown", name: "Jalón al pecho con agarre neutro", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "wed-chest-supported-row", name: "Remo con pecho apoyado", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "wed-cable-pullover", name: "Pullover en polea", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "wed-reverse-pec-deck", name: "Pájaros en máquina / reverse pec deck", sets: 3, repRange: "12–20"),
            ExerciseDefinition(id: "wed-incline-db-curl", name: "Curl inclinado con mancuernas", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "wed-rope-hammer-curl", name: "Curl martillo con cuerda", sets: 2, repRange: "10–15"),
        ]
    )

    static let thursdayLegs = SessionDefinition(
        id: "thu-legs-abs",
        title: "Piernas y abdominales",
        kind: .strength,
        weekday: 4,
        detail: "Tren inferior y core.",
        exercises: [
            ExerciseDefinition(id: "thu-hack-squat", name: "Hack squat", sets: 3, repRange: "6–10"),
            ExerciseDefinition(id: "thu-romanian-deadlift", name: "Peso muerto rumano", sets: 3, repRange: "6–10"),
            ExerciseDefinition(id: "thu-seated-leg-curl", name: "Curl femoral sentado", sets: 3, repRange: "10–15"),
            ExerciseDefinition(id: "thu-leg-extension", name: "Extensión de cuádriceps", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "thu-standing-calf-raise", name: "Elevación de gemelos de pie", sets: 3, repRange: "10–15"),
            ExerciseDefinition(id: "thu-cable-crunch", name: "Crunch en polea", sets: 3, repRange: "10–20"),
        ]
    )

    static let fridayRest = SessionDefinition(
        id: "fri-rest",
        title: "Descanso",
        kind: .rest,
        weekday: 5,
        detail: "Día de recuperación: prioriza el sueño, la hidratación y un paseo suave si te apetece. Sin entrenamiento de fuerza.",
        exercises: []
    )

    static let saturdayRun = SessionDefinition(
        id: "sat-run",
        title: "Sesión 1 · Carrera",
        kind: .run,
        weekday: 6,
        detail: "Correr entre 20 y 30 minutos.",
        exercises: []
    )

    static let saturdayChestBack = SessionDefinition(
        id: "sat-chest-back",
        title: "Sesión 2 · Pecho y espalda",
        kind: .strength,
        weekday: 6,
        detail: "Segunda sesión del sábado, independiente de la carrera.",
        exercises: [
            ExerciseDefinition(id: "sat-smith-incline-press", name: "Press inclinado en multipower", sets: 3, repRange: "6–10"),
            ExerciseDefinition(id: "sat-seated-cable-row", name: "Remo sentado en polea", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "sat-machine-chest-press", name: "Press de pecho en máquina", sets: 2, repRange: "8–12"),
            ExerciseDefinition(id: "sat-neutral-pulldown", name: "Jalón con agarre neutro", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "sat-cable-fly", name: "Aperturas en polea", sets: 2, repRange: "12–15"),
        ]
    )

    static let sundayShouldersArms = SessionDefinition(
        id: "sun-shoulders-arms",
        title: "Hombros y brazos",
        kind: .strength,
        weekday: 7,
        detail: "Deltoides, bíceps, tríceps y antebrazo.",
        exercises: [
            ExerciseDefinition(id: "sun-cable-lateral-raise", name: "Elevación lateral en polea", sets: 3, repRange: "12–20"),
            ExerciseDefinition(id: "sun-reverse-pec-deck", name: "Reverse pec deck", sets: 2, repRange: "12–20"),
            ExerciseDefinition(id: "sun-preacher-curl", name: "Curl predicador", sets: 3, repRange: "8–12"),
            ExerciseDefinition(id: "sun-overhead-triceps-ext", name: "Extensión de tríceps por encima de la cabeza", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "sun-incline-db-curl", name: "Curl inclinado con mancuernas", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "sun-rope-triceps-ext", name: "Extensión de tríceps con cuerda", sets: 2, repRange: "10–15"),
            ExerciseDefinition(id: "sun-ez-reverse-curl", name: "Curl inverso con barra EZ", sets: 2, repRange: "12–15"),
            ExerciseDefinition(id: "sun-wrist-curl", name: "Curl de muñeca", sets: 2, repRange: "12–20"),
        ]
    )

    /// Todas las sesiones en orden semanal. El sábado tiene DOS sesiones separadas.
    static let allSessions: [SessionDefinition] = [
        mondayRun, tuesdayPushA, wednesdayPullA, thursdayLegs, fridayRest,
        saturdayRun, saturdayChestBack, sundayShouldersArms,
    ]

    /// Sesiones entrenables (excluye el descanso). Base del cumplimiento semanal.
    static var trainableSessions: [SessionDefinition] {
        allSessions.filter { $0.kind != .rest }
    }

    /// La semana tal y como la tiene montada el usuario: con sus tipos de día, sus nombres y
    /// sus ejercicios. Todo lo que cuente sesiones debe salir de aquí y no de `allSessions`,
    /// o diría que te faltan entrenos que tú has puesto como descanso.
    static func week(routine: [RoutineExercise] = [],
                     titles: [SessionTitle] = [],
                     kinds: [SessionKindChoice] = []) -> [SessionDefinition] {
        allSessions.map { $0.resolved(with: routine, titles: titles, kinds: kinds) }
    }

    /// Las sesiones que cuentan para el cumplimiento, ya con los cambios del usuario.
    static func trainable(routine: [RoutineExercise] = [],
                          titles: [SessionTitle] = [],
                          kinds: [SessionKindChoice] = []) -> [SessionDefinition] {
        week(routine: routine, titles: titles, kinds: kinds).filter { $0.kind != .rest }
    }

    static func sessions(forWeekday weekday: Int) -> [SessionDefinition] {
        allSessions.filter { $0.weekday == weekday }
    }

    static func session(id: String) -> SessionDefinition? {
        allSessions.first { $0.id == id }
    }

    static let weekdayNames = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    /// Busca un ejercicio de la rutina predeterminada (para nombres de registros antiguos).
    static func defaultExercise(id: String) -> ExerciseDefinition? {
        allSessions.lazy.flatMap(\.exercises).first { $0.id == id }
    }

    static func weekdayName(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "" }
        return weekdayNames[weekday - 1]
    }
}
