import Foundation

/// Ficha de un ejercicio: a qué músculos va, con qué material, cómo se hace y qué se falla.
/// Son descripciones técnicas de entrenamiento, no consejo médico. No se incluyen enlaces
/// ni vídeos: la app no inventa fuentes que no pueda garantizar.
struct ExerciseInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// Otros identificadores que significan el mismo ejercicio (la rutina usa ids por día).
    let aliases: [String]
    let primary: MuscleGroup
    let secondary: [MuscleGroup]
    let pattern: MovementPattern
    let equipment: Equipment
    /// Un lado a la vez (las series se cuentan por lado).
    let isUnilateral: Bool
    let defaultSets: Int
    let defaultRepMin: Int
    let defaultRepMax: Int
    /// Cómo se ejecuta, paso a paso.
    let execution: [String]
    /// Errores que se ven a diario en el gimnasio.
    let mistakes: [String]
    /// Qué vigilar para no hacerse daño. nil si no hay nada específico.
    let safety: String?
    /// En qué se diferencia de sus parientes cercanos.
    let trait: String
    /// Lo ha creado el usuario (no viene en la biblioteca).
    let isCustom: Bool

    init(_ id: String, _ name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [],
         pattern: MovementPattern, equipment: Equipment, unilateral: Bool = false,
         sets: Int = 3, reps: ClosedRange<Int> = 8...12, aliases: [String] = [],
         execution: [String], mistakes: [String], safety: String? = nil, trait: String,
         isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.primary = primary
        self.secondary = secondary
        self.pattern = pattern
        self.equipment = equipment
        self.isUnilateral = unilateral
        self.defaultSets = sets
        self.defaultRepMin = reps.lowerBound
        self.defaultRepMax = reps.upperBound
        self.execution = execution
        self.mistakes = mistakes
        self.safety = safety
        self.trait = trait
        self.isCustom = isCustom
    }

    var defaultRepRange: String { ExerciseDefinition.formatRange(min: defaultRepMin, max: defaultRepMax) }

    /// Todos los músculos implicados, el principal primero.
    var allMuscles: [MuscleGroup] { [primary] + secondary }

    var summary: String {
        var parts = [primary.label]
        if !secondary.isEmpty { parts.append(secondary.map(\.label).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Catálogo

enum ExerciseCatalog {
    /// Prefijos de día que la rutina añade a los identificadores («tue-bench-barbell»).
    static let weekdayPrefixes = ["mon-", "tue-", "wed-", "thu-", "fri-", "sat-", "sun-"]

    /// Quita el prefijo de día de un identificador de rutina.
    static func canonicalID(_ routineID: String) -> String {
        for prefix in weekdayPrefixes where routineID.hasPrefix(prefix) {
            return String(routineID.dropFirst(prefix.count))
        }
        return routineID
    }

    private static let byID: [String: ExerciseInfo] = {
        var map: [String: ExerciseInfo] = [:]
        for info in all {
            map[info.id] = info
            for alias in info.aliases { map[alias] = info }
        }
        return map
    }()

    private static let byName: [String: ExerciseInfo] = {
        var map: [String: ExerciseInfo] = [:]
        for info in all { map[normalize(info.name)] = info }
        return map
    }()

    /// Busca la ficha de un ejercicio de la rutina. Primero por identificador (quitando el día),
    /// y si es un ejercicio que ha creado el usuario, por nombre.
    static func info(id: String, name: String? = nil) -> ExerciseInfo? {
        if let direct = byID[id] { return direct }
        if let canonical = byID[canonicalID(id)] { return canonical }
        if let mine = custom(id: id, name: name) { return mine }
        if let name, let match = byName[normalize(name)] { return match }
        return nil
    }

    static func info(named name: String) -> ExerciseInfo? { byName[normalize(name)] }

    /// La biblioteca y los ejercicios que ha creado el usuario, todo junto.
    static var everything: [ExerciseInfo] { all + customExercises }

    /// Compara sin acentos, sin mayúsculas y sin espacios de más.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: Búsqueda y filtros

    static func search(_ text: String, muscle: MuscleGroup? = nil, pattern: MovementPattern? = nil,
                       equipment: Equipment? = nil) -> [ExerciseInfo] {
        let needle = normalize(text)
        return everything.filter { info in
            if let muscle, !info.allMuscles.contains(muscle) { return false }
            if let pattern, info.pattern != pattern { return false }
            if let equipment, info.equipment != equipment { return false }
            guard !needle.isEmpty else { return true }
            return normalize(info.name).contains(needle) || info.primary.label.lowercased().contains(needle)
        }
        .sorted { ($0.primary, $0.name) < ($1.primary, $1.name) }
    }

    static func byMuscle(_ group: MuscleGroup) -> [ExerciseInfo] {
        everything.filter { $0.primary == group }.sorted { $0.name < $1.name }
    }

    /// Ejercicios que trabajan el mismo músculo principal con el mismo patrón: los candidatos
    /// más razonables para sustituir uno sin cambiar el objetivo de la sesión.
    /// Se ordenan poniendo primero los que comparten patrón y músculo, y luego los del mismo músculo.
    static func alternatives(to info: ExerciseInfo, equipment: Equipment? = nil, limit: Int = 8) -> [ExerciseInfo] {
        let pool = everything
        let samePattern = pool.filter { $0.id != info.id && $0.pattern == info.pattern && $0.primary == info.primary }
        let sameMuscle = pool.filter { $0.id != info.id && $0.primary == info.primary && $0.pattern != info.pattern }
        let ordered = samePattern + sameMuscle
        let filtered = equipment == nil ? ordered : ordered.filter { $0.equipment == equipment }
        return Array(filtered.prefix(limit))
    }

    static func alternatives(forRoutineID id: String, name: String? = nil, equipment: Equipment? = nil) -> [ExerciseInfo] {
        guard let info = info(id: id, name: name) else { return [] }
        return alternatives(to: info, equipment: equipment)
    }

    /// En qué se diferencian dos ejercicios. No dice nunca que sean idénticos.
    static func difference(from a: ExerciseInfo, to b: ExerciseInfo) -> [String] {
        var notes: [String] = []
        if a.equipment != b.equipment {
            notes.append("Material: \(a.equipment.label) → \(b.equipment.label). \(b.equipment.trait)")
        }
        if a.pattern != b.pattern {
            notes.append("Patrón: \(a.pattern.label) → \(b.pattern.label). El músculo principal coincide, pero el gesto no.")
        }
        let lost = Set(a.secondary).subtracting(b.secondary)
        if !lost.isEmpty {
            notes.append("Deja de ayudar: \(lost.sorted().map(\.label).joined(separator: ", ")).")
        }
        let gained = Set(b.secondary).subtracting(a.secondary)
        if !gained.isEmpty {
            notes.append("Entra a ayudar: \(gained.sorted().map(\.label).joined(separator: ", ")).")
        }
        if a.isUnilateral != b.isUnilateral {
            notes.append(b.isUnilateral ? "Pasa a ser a un lado por vez: la serie cuenta por lado."
                                        : "Pasa a trabajar los dos lados a la vez.")
        }
        if notes.isEmpty {
            notes.append("Mismo músculo, mismo patrón y mismo material: cambian el recorrido y la sensación, "
                         + "así que la carga puede no ser la misma.")
        }
        return notes
    }

    // MARK: - Las fichas

    static let all: [ExerciseInfo] = chest + shoulders + back + arms + legs + core

    // MARK: Pecho

    static let chest: [ExerciseInfo] = [
        ExerciseInfo("bench-barbell", "Press de banca con barra",
            primary: .chest, secondary: [.frontDelts, .triceps],
            pattern: .horizontalPush, equipment: .barbell, sets: 3, reps: 6...10,
            execution: [
                "Tumbado, ojos bajo la barra y pies firmes en el suelo.",
                "Agarre algo más ancho que los hombros, muñecas sobre los codos.",
                "Junta los omóplatos y mantén el pecho alto todo el tiempo.",
                "Baja la barra controlada hasta la parte baja del pecho y empuja hasta estirar los codos.",
            ],
            mistakes: [
                "Rebotar la barra en el pecho: te quita el trabajo justo donde más cuesta.",
                "Despegar los omóplatos y perder el pecho alto.",
                "Codos totalmente abiertos a 90°, que castiga el hombro.",
            ],
            safety: "Con cargas altas, usa los topes del rack o que alguien te ayude. Agarra con el pulgar "
            + "rodeando la barra: el agarre sin pulgar es por donde se escapan las barras.",
            trait: "Es el empuje donde más peso vas a mover. La barra fija las manos, así que el recorrido "
            + "es menor que con mancuernas y el pecho trabaja en un rango algo más corto."),

        ExerciseInfo("incline-db-press", "Press inclinado con mancuernas",
            primary: .chest, secondary: [.frontDelts, .triceps],
            pattern: .horizontalPush, equipment: .dumbbell, reps: 8...12,
            execution: [
                "Banco entre 30° y 45°; cuanto más inclinado, más trabaja el hombro.",
                "Sube las mancuernas con la ayuda de las piernas y colócalas a los lados del pecho.",
                "Empuja hacia arriba y ligeramente hacia dentro, sin que choquen.",
                "Baja hasta sentir el pecho estirado, sin forzar el hombro.",
            ],
            mistakes: [
                "Inclinar tanto el banco que se convierte en un press de hombro.",
                "Bajar sin control buscando un estiramiento exagerado.",
                "Chocar las mancuernas arriba y perder la tensión.",
            ],
            trait: "Más recorrido que la barra y cada lado por su cuenta. Carga menos peso total, pero el pecho superior se lleva más."),

        ExerciseInfo("machine-chest-press", "Press de pecho en máquina",
            primary: .chest, secondary: [.frontDelts, .triceps],
            pattern: .horizontalPush, equipment: .machine, sets: 2, reps: 8...12,
            execution: [
                "Ajusta el asiento para que las empuñaduras queden a la altura del pecho medio.",
                "Espalda apoyada y omóplatos juntos.",
                "Empuja hasta casi estirar y vuelve controlando.",
            ],
            mistakes: [
                "Asiento demasiado bajo, que convierte el empuje en un press inclinado.",
                "Despegar la espalda del respaldo para sacar más peso.",
            ],
            trait: "Guiado: es el más seguro para acercarse al fallo sin ayuda. No exige equilibrio, así que entrena menos la estabilidad."),

        ExerciseInfo("smith-incline-press", "Press inclinado en multipower",
            primary: .chest, secondary: [.frontDelts, .triceps],
            pattern: .horizontalPush, equipment: .smith, sets: 3, reps: 6...10,
            execution: [
                "Coloca el banco inclinado de modo que la barra baje a la altura del pecho alto.",
                "Desbloquea la barra girando las muñecas y baja controlando.",
                "Empuja hasta estirar sin bloquear de golpe.",
            ],
            mistakes: [
                "Colocar el banco mal y acabar bajando la barra al cuello.",
                "Olvidar poner los seguros a una altura útil.",
            ],
            safety: "Deja los topes puestos a la altura del pecho: es lo que hace seguro entrenar solo aquí.",
            trait: "La trayectoria va guiada como en una máquina, pero con la sensación de barra. Permite fallar sin compañero."),

        ExerciseInfo("cable-fly", "Aperturas en polea",
            primary: .chest, secondary: [.frontDelts],
            pattern: .shoulderTransverse, equipment: .cable, sets: 2, reps: 12...15,
            execution: [
                "Poleas a la altura del hombro o algo por encima.",
                "Un paso adelante, pecho alto y codos ligeramente flexionados y fijos.",
                "Junta las manos describiendo un arco, sin estirar ni doblar más el codo.",
            ],
            mistakes: [
                "Convertirlo en un press doblando y estirando el codo.",
                "Tirar con tanto peso que el movimiento lo hace el hombro entero.",
            ],
            trait: "Tensión constante y el pecho trabaja cerrando, no empujando. No sustituye a un press: mueve mucho menos peso."),

        ExerciseInfo("pec-deck", "Pec deck / contractora",
            primary: .chest, secondary: [.frontDelts],
            pattern: .shoulderTransverse, equipment: .machine, reps: 10...15,
            execution: [
                "Asiento a la altura que deje los codos a la altura del pecho.",
                "Espalda apoyada y antebrazos en las almohadillas.",
                "Cierra hasta juntar y vuelve controlando sin soltar la tensión.",
            ],
            mistakes: ["Soltar el peso de golpe al volver.", "Encoger los hombros al cerrar."],
            trait: "Igual que las aperturas pero guiado: más fácil de aprender y de llevar al límite."),

        ExerciseInfo("dip-chest", "Fondos en paralelas (énfasis pecho)",
            primary: .chest, secondary: [.triceps, .frontDelts],
            pattern: .horizontalPush, equipment: .bodyweight, reps: 6...12,
            execution: [
                "Agarra las paralelas y estira los codos con el cuerpo algo inclinado hacia delante.",
                "Baja hasta que el hombro quede un poco por debajo del codo.",
                "Empuja manteniendo la inclinación del tronco.",
            ],
            mistakes: [
                "Bajar más de lo que da el hombro buscando recorrido.",
                "Ponerse vertical, que lo convierte en un ejercicio de tríceps.",
            ],
            safety: "Si notas pinchazos en la parte delantera del hombro, reduce el recorrido.",
            trait: "La carga es tu peso; se progresa con lastre. Inclinado va al pecho, vertical al tríceps."),

        ExerciseInfo("push-up", "Flexiones",
            primary: .chest, secondary: [.frontDelts, .triceps, .abs],
            pattern: .horizontalPush, equipment: .bodyweight, reps: 10...20,
            execution: [
                "Manos algo más anchas que los hombros, cuerpo en línea.",
                "Baja hasta que el pecho roce el suelo con los codos a unos 45°.",
                "Empuja sin que la cadera se hunda ni se eleve.",
            ],
            mistakes: ["Hundir la cadera.", "Bajar solo la cabeza en lugar del pecho."],
            trait: "Sin material. Para seguir progresando hace falta lastre, elevar los pies o pasar a un press."),
    ]

    // MARK: Hombros

    static let shoulders: [ExerciseInfo] = [
        ExerciseInfo("machine-shoulder-press", "Press de hombros en máquina",
            primary: .frontDelts, secondary: [.triceps, .sideDelts],
            pattern: .verticalPush, equipment: .machine, sets: 2, reps: 8...12,
            execution: [
                "Asiento de modo que las empuñaduras queden a la altura de los hombros.",
                "Espalda apoyada y costillas abajo (sin arquear la lumbar).",
                "Empuja arriba sin bloquear de golpe y baja controlando.",
            ],
            mistakes: ["Arquear la lumbar para sacar más peso.", "Bajar solo un palmo y no completar el recorrido."],
            trait: "Guiado y estable: fácil de llevar cerca del fallo. El deltoides anterior manda."),

        ExerciseInfo("db-shoulder-press", "Press de hombros con mancuernas",
            primary: .frontDelts, secondary: [.sideDelts, .triceps],
            pattern: .verticalPush, equipment: .dumbbell, reps: 8...12,
            execution: [
                "Sentado con respaldo, mancuernas a la altura de las orejas.",
                "Empuja hasta arriba llevando las manos ligeramente hacia dentro.",
                "Baja hasta que el codo quede algo por debajo del hombro.",
            ],
            mistakes: ["Empujar con la espalda arqueada.", "Dejar que los codos se vayan muy por detrás."],
            trait: "Más recorrido y cada lado por su cuenta. Exige más estabilidad que la máquina."),

        ExerciseInfo("overhead-press-barbell", "Press militar con barra",
            primary: .frontDelts, secondary: [.triceps, .upperBack, .abs],
            pattern: .verticalPush, equipment: .barbell, sets: 3, reps: 5...8,
            execution: [
                "Barra sobre la parte alta del pecho, agarre a la anchura de los hombros.",
                "Aprieta glúteos y abdomen para no arquear la lumbar.",
                "Empuja llevando la cabeza ligeramente atrás y luego la barra sobre la coronilla.",
            ],
            mistakes: ["Convertirlo en un press inclinado de pie.", "Arquear la lumbar al final del empuje."],
            safety: "Si no llegas arriba sin arquear, reduce peso o hazlo sentado con respaldo.",
            trait: "El empuje vertical con más carga posible. Pide movilidad de hombro y un core firme."),

        ExerciseInfo("cable-lateral-raise", "Elevación lateral en polea",
            primary: .sideDelts, secondary: [.traps],
            pattern: .shoulderAbduction, equipment: .cable, unilateral: true, sets: 3, reps: 12...20,
            aliases: ["cable-lateral-raise-single"],
            execution: [
                "Polea abajo, cruzada por delante del cuerpo.",
                "Sube el brazo hacia el lado hasta la altura del hombro, codo casi estirado.",
                "Baja controlando sin dejar que el peso te lleve.",
            ],
            mistakes: [
                "Tirar con el cuerpo cogiendo carrerilla.",
                "Encoger el hombro: el trapecio se lleva el trabajo.",
                "Pasarse de la altura del hombro.",
            ],
            trait: "Tensión constante desde el principio, también abajo, donde la mancuerna no pesa nada. Cuenta por lado."),

        ExerciseInfo("db-lateral-raise", "Elevación lateral con mancuernas",
            primary: .sideDelts, secondary: [.traps],
            pattern: .shoulderAbduction, equipment: .dumbbell, reps: 12...20,
            execution: [
                "De pie, mancuernas a los lados y tronco firme.",
                "Sube hasta la altura del hombro con el codo ligeramente flexionado.",
                "Baja despacio, controlando los últimos centímetros.",
            ],
            mistakes: ["Balancear el cuerpo.", "Subir con los pulgares hacia arriba y los codos muy doblados."],
            trait: "Muy cómodo y sin material especial, pero abajo casi no hay tensión. Dos lados a la vez."),

        ExerciseInfo("machine-lateral-raise", "Elevación lateral en máquina",
            primary: .sideDelts, secondary: [.traps],
            pattern: .shoulderAbduction, equipment: .machine, reps: 12...20,
            execution: [
                "Ajusta el asiento para que el eje quede a la altura del hombro.",
                "Empuja con los codos, no con las manos.",
                "Vuelve controlando sin soltar el peso.",
            ],
            mistakes: ["Eje mal colocado, que cambia por completo la resistencia.", "Ayudarse con el cuerpo."],
            trait: "La más fácil de llevar al fallo con seguridad. Resistencia pensada para todo el recorrido."),

        ExerciseInfo("reverse-pec-deck", "Pájaros en máquina / reverse pec deck",
            primary: .rearDelts, secondary: [.upperBack, .traps],
            pattern: .shoulderTransverse, equipment: .machine, sets: 3, reps: 12...20,
            execution: [
                "Pecho contra el respaldo y empuñaduras a la altura del hombro.",
                "Abre con los codos altos, llevando los brazos hacia atrás.",
                "Vuelve despacio sin dejar que el peso cierre solo.",
            ],
            mistakes: [
                "Juntar los omóplatos con fuerza: eso lo hace la espalda, no el deltoides posterior.",
                "Encoger los hombros al abrir.",
            ],
            trait: "El más sencillo de aislar el deltoides posterior. Si juntas escápulas, se va a la espalda alta."),

        ExerciseInfo("cable-rear-delt-fly", "Pájaros cruzados en polea",
            primary: .rearDelts, secondary: [.upperBack],
            pattern: .shoulderTransverse, equipment: .cable, reps: 12...20,
            execution: [
                "Poleas a la altura del hombro, cruzadas.",
                "Abre en arco con el codo casi fijo.",
                "Para cuando los brazos estén en línea con los hombros.",
            ],
            mistakes: ["Usar demasiado peso y acabar remando.", "Dejar que los brazos pasen muy atrás."],
            trait: "Tensión constante y recorrido ajustable moviendo los pies. Más técnico que la máquina."),

        ExerciseInfo("face-pull", "Face pull",
            primary: .rearDelts, secondary: [.upperBack, .traps],
            pattern: .horizontalPull, equipment: .cable, reps: 12...20,
            execution: [
                "Polea a la altura de la cara con cuerda.",
                "Tira llevando las manos hacia las orejas y los codos altos.",
                "Termina abriendo las manos y rotando los hombros hacia fuera.",
            ],
            mistakes: ["Tirar bajo, a la altura del pecho.", "Mover el tronco hacia atrás para ayudarse."],
            trait: "Trabaja el deltoides posterior junto a la rotación del hombro: suele sentar bien a hombros cargados."),

        ExerciseInfo("barbell-shrug", "Encogimientos con barra",
            primary: .traps, secondary: [.upperBack, .forearms],
            pattern: .shrug, equipment: .barbell, reps: 8...15,
            execution: [
                "Barra delante, brazos estirados y pecho alto.",
                "Sube los hombros hacia las orejas sin doblar los codos.",
                "Baja controlando hasta notar el estiramiento.",
            ],
            mistakes: ["Rotar los hombros en círculos.", "Doblar los codos y convertirlo en un remo."],
            trait: "Para el trapecio superior. El recorrido es corto por naturaleza: no hace falta forzarlo."),
    ]

    // MARK: Espalda

    static let back: [ExerciseInfo] = [
        ExerciseInfo("neutral-lat-pulldown", "Jalón al pecho con agarre neutro",
            primary: .lats, secondary: [.biceps, .upperBack, .rearDelts],
            pattern: .verticalPull, equipment: .cable, sets: 3, reps: 8...12,
            aliases: ["neutral-pulldown"],
            execution: [
                "Fija los muslos bajo las almohadillas y agarra en neutro (palmas enfrentadas).",
                "Lleva los codos abajo y atrás, hacia los bolsillos.",
                "Baja hasta que las manos pasen la altura de la barbilla y sube controlando.",
            ],
            mistakes: [
                "Tirar con el tronco muy echado atrás, que lo convierte en un remo.",
                "Encoger los hombros al final.",
                "Subir soltando y perder la tensión del dorsal.",
            ],
            trait: "El agarre neutro es el más cómodo para el hombro y el codo. El dorsal manda; el bíceps ayuda bastante."),

        ExerciseInfo("wide-lat-pulldown", "Jalón al pecho con agarre ancho",
            primary: .lats, secondary: [.upperBack, .biceps],
            pattern: .verticalPull, equipment: .cable, reps: 8...12,
            execution: [
                "Agarre pronado algo más ancho que los hombros.",
                "Pecho alto y codos hacia abajo.",
                "Baja la barra al pecho alto sin balancear.",
            ],
            mistakes: ["Agarre exageradamente ancho, que recorta el recorrido.", "Llevar la barra detrás del cuello."],
            safety: "Nunca por detrás del cuello: fuerza el hombro sin ninguna ventaja.",
            trait: "Algo más de espalda alta que el neutro y algo menos de bíceps."),

        ExerciseInfo("pull-up", "Dominadas",
            primary: .lats, secondary: [.biceps, .upperBack, .abs],
            pattern: .verticalPull, equipment: .bodyweight, reps: 5...12,
            execution: [
                "Agarre pronado a la anchura de los hombros o algo más.",
                "Empieza con los brazos estirados y los hombros activos.",
                "Sube hasta que la barbilla pase la barra y baja controlando.",
            ],
            mistakes: ["Balancearse para coger impulso.", "No bajar del todo entre repeticiones."],
            trait: "El mejor tirón vertical si tienes fuerza para hacerlo en rango. Se progresa con lastre o asistencia."),

        ExerciseInfo("chest-supported-row", "Remo con pecho apoyado",
            primary: .upperBack, secondary: [.lats, .biceps, .rearDelts],
            pattern: .horizontalPull, equipment: .machine, sets: 3, reps: 8...12,
            execution: [
                "Pecho firme contra el respaldo, pies estables.",
                "Tira llevando los codos atrás, cerca del cuerpo.",
                "Aprieta un instante arriba y vuelve estirando los brazos del todo.",
            ],
            mistakes: [
                "Despegar el pecho del respaldo para tirar más.",
                "Tirar solo con los brazos sin mover los omóplatos.",
            ],
            trait: "Al estar apoyado, la lumbar no participa: todo el trabajo va a la espalda. Ideal para acumular volumen."),

        ExerciseInfo("seated-cable-row", "Remo sentado en polea",
            primary: .upperBack, secondary: [.lats, .biceps, .rearDelts],
            pattern: .horizontalPull, equipment: .cable, sets: 3, reps: 8...12,
            execution: [
                "Sentado con las rodillas algo flexionadas y el pecho alto.",
                "Tira hacia el abdomen con los codos pegados.",
                "Vuelve dejando que los brazos se estiren sin encorvar la espalda.",
            ],
            mistakes: ["Mecerse adelante y atrás con todo el tronco.", "Encorvar la espalda al estirar los brazos."],
            trait: "Tensión constante y recorrido largo. Exige que el tronco se mantenga quieto por sí mismo."),

        ExerciseInfo("barbell-row", "Remo con barra",
            primary: .upperBack, secondary: [.lats, .biceps, .lowerBack, .hamstrings],
            pattern: .horizontalPull, equipment: .barbell, sets: 3, reps: 6...10,
            execution: [
                "Tronco inclinado unos 45°, espalda recta y rodillas algo flexionadas.",
                "Tira la barra hacia el ombligo con los codos cerca del cuerpo.",
                "Baja controlando sin perder la posición del tronco.",
            ],
            mistakes: ["Subir el tronco a la vez que la barra.", "Redondear la espalda baja."],
            safety: "Si la lumbar se redondea, baja el peso. La posición del tronco no es negociable.",
            trait: "Mucha carga, pero la lumbar y los femorales trabajan para sostenerte: cansa más de lo que parece."),

        ExerciseInfo("db-row", "Remo con mancuerna a una mano",
            primary: .lats, secondary: [.upperBack, .biceps],
            pattern: .horizontalPull, equipment: .dumbbell, unilateral: true, reps: 8...12,
            execution: [
                "Una mano y una rodilla en el banco, espalda plana.",
                "Tira la mancuerna hacia la cadera con el codo cerca.",
                "Estira el brazo del todo abajo.",
            ],
            mistakes: ["Rotar el tronco para subir más peso.", "Tirar hacia el hombro en lugar de la cadera."],
            trait: "Recorrido largo y cada lado por separado. La serie cuenta por lado."),

        ExerciseInfo("cable-pullover", "Pullover en polea",
            primary: .lats, secondary: [.chest, .triceps],
            pattern: .pullover, equipment: .cable, sets: 2, reps: 10...15,
            execution: [
                "Polea alta, de pie y algo inclinado hacia delante.",
                "Brazos casi estirados: baja llevando las manos hacia los muslos.",
                "Sube controlando hasta notar el dorsal estirado.",
            ],
            mistakes: ["Doblar los codos y convertirlo en un jalón.", "Mover el tronco arriba y abajo."],
            trait: "Trabaja el dorsal sin que participe el bíceps: es el complemento natural de los jalones."),

        ExerciseInfo("straight-arm-pulldown", "Jalón con brazos estirados",
            primary: .lats, secondary: [.chest],
            pattern: .pullover, equipment: .cable, reps: 10...15,
            execution: [
                "Polea alta con barra recta, un paso atrás y tronco inclinado.",
                "Baja la barra hasta los muslos con los codos fijos.",
                "Vuelve arriba sin encoger los hombros.",
            ],
            mistakes: ["Flexionar los codos.", "Usar tanto peso que el cuerpo sube y baja."],
            trait: "Prácticamente lo mismo que el pullover en polea, con la barra en vez de la cuerda."),

        ExerciseInfo("t-bar-row", "Remo en T",
            primary: .upperBack, secondary: [.lats, .biceps, .lowerBack],
            pattern: .horizontalPull, equipment: .barbell, reps: 8...12,
            execution: [
                "De pie sobre la plataforma, tronco inclinado y espalda recta.",
                "Tira con los codos atrás hasta tocar el pecho o el abdomen.",
                "Baja controlando sin redondear.",
            ],
            mistakes: ["Dar tirones con la cadera.", "Usar un rango muy corto por exceso de peso."],
            trait: "Como el remo con barra pero más estable; aun así la lumbar sigue trabajando."),

        ExerciseInfo("back-extension", "Extensión lumbar",
            primary: .lowerBack, secondary: [.glutes, .hamstrings],
            pattern: .hipExtension, equipment: .bodyweight, reps: 10...15,
            execution: [
                "Cadera justo en el borde del banco.",
                "Baja flexionando la cadera con la espalda recta.",
                "Sube hasta alinear el tronco, sin pasarte hacia atrás.",
            ],
            mistakes: ["Hiperextender la espalda arriba.", "Bajar redondeando la zona lumbar."],
            safety: "Para en la línea del cuerpo: pasarse hacia atrás no aporta nada y carga las vértebras.",
            trait: "Trabaja la cadena posterior sin cargar las rodillas ni necesitar peso."),
    ]

    // MARK: Brazos

    static let arms: [ExerciseInfo] = [
        ExerciseInfo("incline-db-curl", "Curl inclinado con mancuernas",
            primary: .biceps, secondary: [.forearms],
            pattern: .elbowFlexion, equipment: .dumbbell, sets: 3, reps: 8...12,
            execution: [
                "Banco inclinado hacia atrás unos 45–60°, brazos colgando.",
                "Flexiona el codo sin que el brazo se adelante.",
                "Baja hasta estirar del todo y nota el estiramiento del bíceps.",
            ],
            mistakes: ["Adelantar el hombro para ayudarse.", "No estirar abajo, que es la parte que más aporta aquí."],
            trait: "El bíceps empieza estirado, lo que lo hace muy exigente abajo. Con poco peso ya sobra."),

        ExerciseInfo("preacher-curl", "Curl predicador",
            primary: .biceps, secondary: [.forearms],
            pattern: .elbowFlexion, equipment: .ezBar, sets: 3, reps: 8...12,
            execution: [
                "Axilas apoyadas en el soporte y brazos pegados al respaldo.",
                "Sube flexionando el codo hasta donde el banco lo permita.",
                "Baja controlando hasta casi estirar.",
            ],
            mistakes: ["Despegar los codos del soporte.", "Dejar caer el peso en la bajada."],
            safety: "No estires el codo de golpe en la última repetición: hazlo controlado.",
            trait: "Bloquea el hombro, así que el bíceps no tiene escapatoria. La bajada es la parte delicada."),

        ExerciseInfo("rope-hammer-curl", "Curl martillo con cuerda",
            primary: .biceps, secondary: [.forearms],
            pattern: .elbowFlexion, equipment: .cable, sets: 2, reps: 10...15,
            execution: [
                "Polea baja con cuerda, agarre neutro (pulgares arriba).",
                "Flexiona los codos manteniéndolos pegados al tronco.",
                "Baja controlando sin que los codos se vayan atrás.",
            ],
            mistakes: ["Mover los codos hacia atrás al subir.", "Tirar con el tronco."],
            trait: "El agarre neutro mete al braquial y al antebrazo: suele permitir más carga que el curl supino."),

        ExerciseInfo("db-curl", "Curl con mancuernas",
            primary: .biceps, secondary: [.forearms],
            pattern: .elbowFlexion, equipment: .dumbbell, reps: 8...12,
            execution: [
                "De pie o sentado, brazos a los lados.",
                "Sube flexionando el codo, girando ligeramente la palma hacia arriba.",
                "Baja del todo controlando.",
            ],
            mistakes: ["Balancear el cuerpo.", "Subir los codos hacia delante."],
            trait: "El clásico. Permite girar la mano, que es donde el bíceps hace su segunda función."),

        ExerciseInfo("ez-reverse-curl", "Curl inverso con barra EZ",
            primary: .forearms, secondary: [.biceps],
            pattern: .elbowFlexion, equipment: .ezBar, sets: 2, reps: 12...15,
            execution: [
                "Agarre pronado (palmas abajo) en la parte angulada de la barra.",
                "Sube flexionando el codo sin mover los hombros.",
                "Baja controlando.",
            ],
            mistakes: ["Usar demasiado peso: aquí se nota enseguida.", "Dejar que las muñecas se doblen hacia abajo."],
            trait: "Va al antebrazo y al braquial más que al bíceps. Mueve bastante menos peso que el curl normal."),

        ExerciseInfo("wrist-curl", "Curl de muñeca",
            primary: .forearms, secondary: [],
            pattern: .wristFlexion, equipment: .dumbbell, sets: 2, reps: 12...20,
            execution: [
                "Antebrazos apoyados en el banco o los muslos, manos fuera del borde.",
                "Deja caer la muñeca y súbela flexionándola.",
                "Hazlo despacio: el recorrido es corto.",
            ],
            mistakes: ["Mover el codo.", "Cargar tanto que la muñeca no completa el recorrido."],
            trait: "Trabajo directo del antebrazo. Recorrido corto, así que el control importa más que el peso."),

        ExerciseInfo("overhead-triceps-ext", "Extensión de tríceps por encima de la cabeza",
            primary: .triceps, secondary: [],
            pattern: .elbowExtension, equipment: .cable, sets: 2, reps: 10...15,
            execution: [
                "De espaldas a la polea, cuerda por encima de la cabeza y codos apuntando al frente.",
                "Estira los codos sin que se abran a los lados.",
                "Vuelve hasta notar el tríceps estirado detrás del brazo.",
            ],
            mistakes: ["Abrir los codos hacia fuera.", "Mover los hombros arriba y abajo."],
            safety: "Si notas molestias en el codo, reduce el recorrido final del estiramiento.",
            trait: "Con el brazo arriba, la cabeza larga del tríceps queda estirada: es la posición que más la trabaja."),

        ExerciseInfo("rope-triceps-ext", "Extensión de tríceps con cuerda",
            primary: .triceps, secondary: [],
            pattern: .elbowExtension, equipment: .cable, sets: 2, reps: 10...15,
            execution: [
                "Polea alta con cuerda, codos pegados al cuerpo.",
                "Estira abriendo las manos al final.",
                "Vuelve sin dejar que los codos se adelanten.",
            ],
            mistakes: ["Inclinar el tronco para empujar con el pecho.", "Separar los codos del cuerpo."],
            trait: "Con el brazo abajo se carga menos la cabeza larga, pero se puede llevar al fallo con mucha comodidad."),

        ExerciseInfo("triceps-pushdown-bar", "Extensión de tríceps en polea con barra",
            primary: .triceps, secondary: [],
            pattern: .elbowExtension, equipment: .cable, reps: 10...15,
            execution: [
                "Polea alta con barra recta o en V, codos al costado.",
                "Estira los codos del todo y vuelve controlando.",
            ],
            mistakes: ["Usar el peso del cuerpo echándose encima.", "No estirar del todo."],
            trait: "Permite más carga que la cuerda; el agarre fijo es menos amable con muñecas sensibles."),

        ExerciseInfo("skull-crusher", "Press francés",
            primary: .triceps, secondary: [],
            pattern: .elbowExtension, equipment: .ezBar, reps: 8...12,
            execution: [
                "Tumbado, barra EZ sobre el pecho con los brazos verticales.",
                "Baja la barra hacia la frente o algo por detrás doblando solo el codo.",
                "Estira sin bloquear de golpe.",
            ],
            mistakes: ["Mover los hombros y convertirlo en un press.", "Bajar demasiado rápido."],
            safety: "Hazlo con barra EZ si los codos te molestan, y nunca sobre la cara sin control.",
            trait: "Pone el tríceps en una posición estirada con mucha carga. Exige codos sanos."),

        ExerciseInfo("dip-triceps", "Fondos en paralelas (énfasis tríceps)",
            primary: .triceps, secondary: [.chest, .frontDelts],
            pattern: .elbowExtension, equipment: .bodyweight, reps: 6...12,
            execution: [
                "Tronco lo más vertical posible y codos pegados.",
                "Baja hasta unos 90° de codo.",
                "Empuja hasta estirar.",
            ],
            mistakes: ["Inclinarse hacia delante (pasa a ser de pecho).", "Bajar demasiado."],
            trait: "El ejercicio de tríceps con más carga posible: tu propio peso. Se progresa con lastre."),
    ]

    // MARK: Piernas

    static let legs: [ExerciseInfo] = [
        ExerciseInfo("hack-squat", "Hack squat",
            primary: .quads, secondary: [.glutes, .adductors],
            pattern: .squat, equipment: .machine, sets: 3, reps: 6...10,
            execution: [
                "Espalda y hombros apoyados, pies a la anchura de la cadera.",
                "Baja hasta que el muslo pase de la paralela, controlando.",
                "Empuja con todo el pie sin bloquear la rodilla de golpe.",
            ],
            mistakes: [
                "Despegar la cadera del respaldo abajo.",
                "Hacer medio recorrido con mucho peso.",
                "Dejar que las rodillas se vayan hacia dentro.",
            ],
            safety: "Comprueba los topes antes de cargar: son lo que te deja fallar sin riesgo.",
            trait: "Sentadilla guiada: casi todo el trabajo va al cuádriceps y el tronco no limita. Lo más seguro para ir al fallo."),

        ExerciseInfo("back-squat", "Sentadilla con barra",
            primary: .quads, secondary: [.glutes, .adductors, .lowerBack, .hamstrings],
            pattern: .squat, equipment: .barbell, sets: 3, reps: 5...8,
            execution: [
                "Barra apoyada en la espalda alta, pies a la anchura de los hombros.",
                "Desciende llevando la cadera atrás y abajo, con el pecho alto.",
                "Baja al menos hasta la paralela y sube empujando el suelo.",
            ],
            mistakes: ["Que los talones se levanten.", "Redondear la espalda baja al final de la bajada."],
            safety: "Siempre dentro del rack con los topes a la altura adecuada.",
            trait: "El ejercicio de pierna con más carga, pero el tronco y la lumbar se cansan antes que el cuádriceps."),

        ExerciseInfo("leg-press", "Prensa de piernas",
            primary: .quads, secondary: [.glutes, .adductors],
            pattern: .squat, equipment: .machine, reps: 8...15,
            execution: [
                "Espalda y cadera pegadas al respaldo, pies a media altura de la plataforma.",
                "Baja hasta unos 90° de rodilla sin que la cadera se despegue.",
                "Empuja sin bloquear las rodillas del todo.",
            ],
            mistakes: ["Dejar que la lumbar se despegue abajo.", "Bloquear las rodillas arriba con todo el peso."],
            trait: "Permite mucha carga sin que el tronco limite. Según dónde pongas los pies, va más a cuádriceps o a glúteo."),

        ExerciseInfo("leg-extension", "Extensión de cuádriceps",
            primary: .quads, secondary: [],
            pattern: .kneeExtension, equipment: .machine, sets: 2, reps: 10...15,
            execution: [
                "Ajusta el respaldo para que la rodilla coincida con el eje de giro.",
                "Estira la rodilla del todo y aprieta un instante.",
                "Baja controlando sin soltar el peso.",
            ],
            mistakes: ["Dar tirones con la cadera.", "Soltar el peso de golpe al bajar."],
            trait: "El único que aísla el cuádriceps sin que el glúteo ayude. No sustituye a una sentadilla."),

        ExerciseInfo("romanian-deadlift", "Peso muerto rumano",
            primary: .hamstrings, secondary: [.glutes, .lowerBack, .upperBack],
            pattern: .hinge, equipment: .barbell, sets: 3, reps: 6...10,
            execution: [
                "De pie con la barra pegada a los muslos y rodillas algo flexionadas.",
                "Lleva la cadera atrás bajando la barra pegada a la pierna.",
                "Baja hasta notar el femoral estirado y sube extendiendo la cadera.",
            ],
            mistakes: [
                "Convertirlo en una sentadilla doblando mucho la rodilla.",
                "Redondear la espalda al bajar.",
                "Separar la barra del cuerpo.",
            ],
            safety: "El recorrido lo marca el estiramiento del femoral con la espalda recta, no el suelo.",
            trait: "La mejor bisagra de cadera para femoral y glúteo. Exige una espalda que aguante la posición."),

        ExerciseInfo("seated-leg-curl", "Curl femoral sentado",
            primary: .hamstrings, secondary: [.calves],
            pattern: .kneeFlexion, equipment: .machine, sets: 3, reps: 10...15,
            execution: [
                "Ajusta el respaldo y la almohadilla justo por encima del talón.",
                "Flexiona la rodilla del todo y aprieta.",
                "Vuelve controlando sin estirar de golpe.",
            ],
            mistakes: ["Levantar la cadera del asiento.", "Hacer medio recorrido."],
            trait: "Sentado, el femoral está más estirado que tumbado: es la versión que suele dar más resultado."),

        ExerciseInfo("lying-leg-curl", "Curl femoral tumbado",
            primary: .hamstrings, secondary: [.calves],
            pattern: .kneeFlexion, equipment: .machine, reps: 10...15,
            execution: [
                "Tumbado con la almohadilla sobre los talones y la cadera pegada al banco.",
                "Flexiona llevando los talones al glúteo.",
                "Baja controlando.",
            ],
            mistakes: ["Levantar la cadera para ayudarse.", "Soltar el peso en la bajada."],
            trait: "Como el sentado, pero con la cadera estirada: se nota distinto y suele permitir algo más de peso."),

        ExerciseInfo("hip-thrust", "Hip thrust",
            primary: .glutes, secondary: [.hamstrings, .quads],
            pattern: .hipExtension, equipment: .barbell, reps: 8...15,
            execution: [
                "Espalda alta apoyada en el banco y barra sobre la cadera, con protección.",
                "Empuja con los talones extendiendo la cadera hasta alinear el tronco.",
                "Aprieta arriba y baja controlando.",
            ],
            mistakes: ["Hiperextender la lumbar arriba en vez de extender la cadera.", "Rango demasiado corto."],
            trait: "El que más carga directa pone en el glúteo. La rodilla trabaja poco."),

        ExerciseInfo("bulgarian-split-squat", "Zancada búlgara",
            primary: .quads, secondary: [.glutes, .adductors, .hamstrings],
            pattern: .lunge, equipment: .dumbbell, unilateral: true, reps: 8...12,
            execution: [
                "Pie de atrás sobre el banco y el de delante bien asentado.",
                "Baja vertical hasta que el muslo de delante pase la paralela.",
                "Empuja con la pierna de delante sin apoyarte en la de atrás.",
            ],
            mistakes: ["Pie de delante demasiado cerca del banco.", "Empujar con la pierna de atrás."],
            trait: "Mucho estímulo con poco peso y cada pierna por separado. La serie cuenta por pierna."),

        ExerciseInfo("standing-calf-raise", "Elevación de gemelos de pie",
            primary: .calves, secondary: [],
            pattern: .calfRaise, equipment: .machine, sets: 3, reps: 10...15,
            execution: [
                "Puntas en el escalón y talones libres.",
                "Baja el talón hasta notar el estiramiento y sube hasta arriba del todo.",
                "Para un instante arriba y abajo: el recorrido es corto y rebotar no cuenta.",
            ],
            mistakes: ["Rebotar sin control.", "Doblar la rodilla para ayudarse."],
            trait: "De pie, con la rodilla estirada, trabaja el gemelo. Sentado va más al sóleo."),

        ExerciseInfo("seated-calf-raise", "Elevación de gemelos sentado",
            primary: .calves, secondary: [],
            pattern: .calfRaise, equipment: .machine, reps: 12...20,
            execution: [
                "Sentado con las rodillas dobladas y las puntas en el apoyo.",
                "Sube y baja despacio, completando el recorrido.",
            ],
            mistakes: ["Rango corto.", "Usar las manos para empujar las rodillas."],
            trait: "Con la rodilla doblada el gemelo pierde protagonismo y trabaja más el sóleo. Complementa al de pie."),

        ExerciseInfo("hip-adduction", "Aducción de cadera en máquina",
            primary: .adductors, secondary: [.glutes],
            pattern: .hipAbduction, equipment: .machine, reps: 12...20,
            execution: [
                "Sentado con las almohadillas por dentro de los muslos y las piernas abiertas.",
                "Cierra las piernas controlando hasta juntarlas.",
                "Vuelve despacio hasta notar el estiramiento, sin llegar al tope de golpe.",
            ],
            mistakes: ["Dejar que el peso te abra las piernas de golpe.", "Hacer un recorrido mínimo con mucho peso."],
            safety: "No busques una apertura máxima con carga: abre solo hasta donde controles.",
            trait: "Es el único trabajo directo de aductores sin tener que hacer sentadillas muy abiertas."),

        ExerciseInfo("hip-abduction", "Abducción de cadera en máquina",
            primary: .glutes, secondary: [],
            pattern: .hipAbduction, equipment: .machine, reps: 12...20,
            execution: [
                "Sentado con las almohadillas por fuera de los muslos.",
                "Abre las piernas controlando y vuelve sin soltar.",
            ],
            mistakes: ["Usar el tronco para empujar.", "Hacer el recorrido a tirones."],
            trait: "Trabaja el glúteo medio, que casi ningún otro ejercicio toca de forma directa."),
    ]

    // MARK: Core

    static let core: [ExerciseInfo] = [
        ExerciseInfo("cable-crunch", "Crunch en polea",
            primary: .abs, secondary: [.obliques],
            pattern: .coreFlexion, equipment: .cable, sets: 3, reps: 10...20,
            execution: [
                "De rodillas frente a la polea alta con la cuerda a los lados de la cabeza.",
                "Flexiona el tronco llevando los codos hacia los muslos.",
                "Vuelve controlando sin que la cadera se mueva.",
            ],
            mistakes: ["Tirar con los brazos.", "Mover la cadera en lugar de flexionar el tronco."],
            trait: "Abdomen con carga progresiva, que es lo que permite progresar de verdad. Mejor que repetir crunches sin peso."),

        ExerciseInfo("hanging-leg-raise", "Elevación de piernas colgado",
            primary: .abs, secondary: [.obliques, .forearms],
            pattern: .coreFlexion, equipment: .bodyweight, reps: 8...15,
            execution: [
                "Colgado de la barra, hombros activos.",
                "Sube las piernas enrollando la pelvis, no solo levantando los muslos.",
                "Baja controlando sin balancearte.",
            ],
            mistakes: ["Balancearse.", "Levantar solo las piernas sin mover la pelvis."],
            trait: "Exige agarre y control. Si te balanceas, mejor hacerlo en la silla romana."),

        ExerciseInfo("plank", "Plancha",
            primary: .abs, secondary: [.obliques, .lowerBack],
            pattern: .coreAntiExtension, equipment: .bodyweight, reps: 1...1,
            execution: [
                "Antebrazos y puntas de los pies en el suelo, cuerpo en línea.",
                "Aprieta abdomen y glúteos y respira con normalidad.",
                "Aguanta el tiempo marcado sin que la cadera caiga.",
            ],
            mistakes: ["Hundir la cadera.", "Aguantar mucho tiempo con mala posición."],
            trait: "Se mide en segundos, no en repeticiones. Entrena aguantar la postura, no flexionar el tronco."),

        ExerciseInfo("cable-rotation", "Rotación en polea",
            primary: .obliques, secondary: [.abs],
            pattern: .coreRotation, equipment: .cable, unilateral: true, reps: 10...15,
            execution: [
                "Polea a la altura del pecho, de lado.",
                "Gira el tronco llevando las manos al otro lado, con los brazos casi estirados.",
                "Vuelve controlando el giro.",
            ],
            mistakes: ["Girar solo con los brazos.", "Dejar que la cadera gire sin control."],
            trait: "Trabaja los oblicuos girando, que es su función. Cuenta por lado."),

        ExerciseInfo("ab-wheel", "Rueda abdominal",
            primary: .abs, secondary: [.obliques, .lats],
            pattern: .coreAntiExtension, equipment: .plate, reps: 8...15,
            execution: [
                "De rodillas con la rueda bajo los hombros.",
                "Rueda hacia delante todo lo que puedas sin que la lumbar se arquee.",
                "Vuelve tirando con el abdomen.",
            ],
            mistakes: ["Arquear la lumbar al estirarse.", "Hacer el recorrido con la cadera."],
            safety: "El recorrido lo marca el punto en que la lumbar empieza a arquearse.",
            trait: "Antiextensión con mucho recorrido. Más exigente de lo que parece."),
    ]
}
