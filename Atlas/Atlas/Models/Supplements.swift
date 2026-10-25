import Foundation

/// Suplementos: qué llevas, cuánto, cuándo y qué cuesta al mes, con lo que se sabe de cada uno.
///
/// Reglas de la app:
/// · Solo aparecen suplementos de venta normal. Nada de sustancias de uso médico ni dopantes.
/// · El nivel de evidencia va escrito: no se vende como probado lo que no lo está.
/// · Detecta que lleves lo mismo dos veces y avisa de excesos evidentes (como la cafeína).
/// · No sustituye a un médico ni a un dietista-nutricionista, y lo dice.

enum EvidenceLevel: String, Codable, CaseIterable, Identifiable, Comparable {
    /// Muchos estudios en la misma dirección.
    case strong
    /// Evidencia razonable, con matices o efectos pequeños.
    case moderate
    /// Pocos estudios, resultados mezclados o solo en casos concretos.
    case limited
    /// No hay base para esperar efecto sobre el rendimiento o la masa muscular.
    case insufficient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strong: return "Evidencia sólida"
        case .moderate: return "Evidencia moderada"
        case .limited: return "Evidencia limitada"
        case .insufficient: return "Sin evidencia suficiente"
        }
    }

    var short: String {
        switch self {
        case .strong: return "Sólida"
        case .moderate: return "Moderada"
        case .limited: return "Limitada"
        case .insufficient: return "Insuficiente"
        }
    }

    var order: Int { EvidenceLevel.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: EvidenceLevel, b: EvidenceLevel) -> Bool { a.order < b.order }
}

enum DoseUnit: String, Codable, CaseIterable, Identifiable {
    case gram, milligram, milliliter, capsule, scoop, internationalUnit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gram: return "g"
        case .milligram: return "mg"
        case .milliliter: return "ml"
        case .capsule: return "cápsulas"
        case .scoop: return "cacitos"
        case .internationalUnit: return "UI"
        }
    }

    /// Convierte a miligramos cuando tiene sentido (para sumar cafeína, por ejemplo).
    func milligrams(_ amount: Double) -> Double? {
        switch self {
        case .gram: return amount * 1000
        case .milligram: return amount
        default: return nil
        }
    }
}

/// Lo que se sabe de un suplemento.
struct SupplementInfo: Identifiable, Hashable {
    let id: String
    let name: String
    /// Principio activo, para detectar que lo lleves dos veces en productos distintos.
    let ingredient: String
    let evidence: EvidenceLevel
    /// Dosis habitual en los estudios.
    let typicalDose: String
    /// Cuándo se suele tomar.
    let timing: String
    /// Para qué sirve, según lo que se ha medido.
    let benefits: [String]
    /// Lo que NO hace, o en qué condiciones no sirve.
    let limits: [String]
    /// Efectos molestos o motivos para consultar antes.
    let risks: [String]
    /// true si conviene hablarlo con un profesional antes de tomarlo.
    let consultFirst: Bool

    init(_ id: String, _ name: String, ingredient: String, evidence: EvidenceLevel,
         typicalDose: String, timing: String, benefits: [String], limits: [String],
         risks: [String] = [], consultFirst: Bool = false) {
        self.id = id
        self.name = name
        self.ingredient = ingredient
        self.evidence = evidence
        self.typicalDose = typicalDose
        self.timing = timing
        self.benefits = benefits
        self.limits = limits
        self.risks = risks
        self.consultFirst = consultFirst
    }
}

enum SupplementCatalog {
    static let disclaimer = "Esta información es general y no sustituye a un médico ni a un dietista-nutricionista. "
        + "Si tomas medicación, estás embarazada o tienes alguna patología, consúltalo antes."

    static let all: [SupplementInfo] = [
        SupplementInfo("creatine", "Creatina monohidrato", ingredient: "creatina", evidence: .strong,
            typicalDose: "3–5 g al día, todos los días. La fase de carga (unos 20 g al día repartidos durante "
            + "5–7 días) solo sirve para llenar los depósitos antes; no es obligatoria.",
            timing: "A cualquier hora. Lo que cuenta es tomarla a diario, no el momento.",
            benefits: ["Más rendimiento en esfuerzos cortos e intensos, que son casi todas las series de fuerza.",
                       "Con el tiempo, algo más de fuerza y de masa muscular que entrenando igual sin ella.",
                       "Es el suplemento más estudiado para el gimnasio y el que mejor relación precio-efecto tiene."],
            limits: ["No sustituye entrenar ni comer suficiente proteína.",
                     "El monohidrato es la forma estudiada; las versiones «mejoradas» cuestan más sin ventaja demostrada.",
                     "Hay personas que responden poco: no es un fallo tuyo ni del producto."],
            risks: ["Al empezar puede notarse algo de retención de agua y 1–2 kg más en la báscula; es agua, no grasa.",
                    "Con dosis muy altas de golpe puede sentar mal al estómago: mejor repartirla."]),

        SupplementInfo("whey", "Proteína de suero (whey)", ingredient: "proteína de suero", evidence: .strong,
            typicalDose: "20–40 g por toma, lo que te falte para llegar a tu objetivo diario de proteína.",
            timing: "A cualquier hora del día. Lo que importa es el total del día, no la ventana post-entreno.",
            benefits: ["Es una forma cómoda y barata de llegar a la proteína del día.",
                       "Digestión rápida y buen perfil de aminoácidos."],
            limits: ["Es comida, no un suplemento mágico: si ya llegas a tu proteína comiendo, no añade nada.",
                     "No hace falta tomarla justo al terminar de entrenar."],
            risks: ["Si te sienta mal la lactosa, el aislado suele tolerarse mejor."]),

        SupplementInfo("caffeine", "Cafeína", ingredient: "cafeína", evidence: .strong,
            typicalDose: "3–6 mg por kg de peso. Para 80 kg, unos 240–480 mg, aunque mucha gente nota ya con 150–200 mg.",
            timing: "30–60 minutos antes de entrenar.",
            benefits: ["Menos esfuerzo percibido: las series duras se llevan mejor.",
                       "Algo más de fuerza y de repeticiones, y mejor resistencia."],
            limits: ["Se genera tolerancia: si la tomas a diario, el efecto agudo baja.",
                     "No compensa dormir poco; a medio plazo lo empeora."],
            risks: ["Tomada por la tarde o la noche empeora el sueño, aunque te duermas igual.",
                    "Puede dar nerviosismo, taquicardia o malestar de estómago.",
                    "Vigila el total del día: café, refrescos y preentrenos suman."]),

        SupplementInfo("beta-alanine", "Beta-alanina", ingredient: "beta-alanina", evidence: .moderate,
            typicalDose: "3,2–6,4 g al día, repartidos. Tarda semanas en hacer efecto porque lo que sube es la carnosina muscular.",
            timing: "A diario, en varias tomas para notar menos el hormigueo.",
            benefits: ["Ayuda en esfuerzos de aproximadamente 1 a 4 minutos.",
                       "En el gimnasio, útil sobre todo en series largas y rangos altos de repeticiones."],
            limits: ["En series de pocas repeticiones apenas se nota.", "No sirve tomada solo el día del entreno."],
            risks: ["Hormigueo en cara y manos (parestesia): es molesto, no peligroso, y baja repartiendo la dosis."]),

        SupplementInfo("citrulline", "Citrulina malato", ingredient: "citrulina", evidence: .limited,
            typicalDose: "6–8 g unos 60 minutos antes.",
            timing: "Antes de entrenar.",
            benefits: ["Algunos estudios ven alguna repetición más y menos fatiga percibida."],
            limits: ["Los resultados están mezclados y los efectos son pequeños.",
                     "La sensación de congestión no significa más músculo."],
            risks: ["Puede dar molestias digestivas a dosis altas."]),

        SupplementInfo("vitamin-d", "Vitamina D", ingredient: "vitamina D", evidence: .moderate,
            typicalDose: "Depende de tu nivel en sangre. No se adivina: se mide.",
            timing: "Con una comida que lleve grasa.",
            benefits: ["Corregir una deficiencia real importa para el hueso, el sistema inmune y la función muscular."],
            limits: ["Si no tienes deficiencia, suplementarla no mejora el rendimiento."],
            risks: ["A dosis altas mantenidas puede ser tóxica: la dosis la decide un profesional con una analítica."],
            consultFirst: true),

        SupplementInfo("omega-3", "Omega 3 (EPA y DHA)", ingredient: "omega 3", evidence: .moderate,
            typicalDose: "1–2 g al día de EPA + DHA (mira la etiqueta: no es lo mismo que gramos de aceite).",
            timing: "Con una comida.",
            benefits: ["Interesante para la salud cardiovascular, sobre todo si comes poco pescado azul."],
            limits: ["Como ayuda directa para ganar músculo, el efecto es pequeño o nulo."],
            risks: ["A dosis altas puede aumentar el riesgo de sangrado; si tomas anticoagulantes, consúltalo."],
            consultFirst: true),

        SupplementInfo("magnesium", "Magnesio", ingredient: "magnesio", evidence: .limited,
            typicalDose: "200–400 mg al día de una forma bien absorbida (citrato, bisglicinato).",
            timing: "Suele tomarse por la noche.",
            benefits: ["Si tienes un consumo bajo, corregirlo tiene sentido."],
            limits: ["No es un somnífero ni mejora el rendimiento si ya comes suficiente magnesio.",
                     "El óxido de magnesio se absorbe mal."],
            risks: ["A dosis altas da diarrea."]),

        SupplementInfo("beetroot", "Remolacha / nitratos", ingredient: "nitrato", evidence: .moderate,
            typicalDose: "Equivalente a 300–600 mg de nitrato, 2–3 horas antes.",
            timing: "Antes de un esfuerzo largo.",
            benefits: ["Mejora la eficiencia en esfuerzos de resistencia como correr."],
            limits: ["En entrenamiento de fuerza el efecto es muy pequeño.",
                     "Los enjuagues bucales antisépticos anulan parte del efecto."],
            risks: ["Puede teñir la orina de rojo; es normal."]),

        SupplementInfo("bicarbonate", "Bicarbonato sódico", ingredient: "bicarbonato", evidence: .moderate,
            typicalDose: "0,2–0,3 g por kg, 60–180 minutos antes.",
            timing: "Antes de un esfuerzo intenso y sostenido.",
            benefits: ["Ayuda en esfuerzos máximos de 1 a 10 minutos."],
            limits: ["Poco aplicable a series de gimnasio normales."],
            risks: ["Molestias digestivas frecuentes y notables.", "Aporta bastante sodio: cuidado si vigilas la tensión."],
            consultFirst: true),

        SupplementInfo("collagen", "Colágeno con vitamina C", ingredient: "colágeno", evidence: .limited,
            typicalDose: "15 g con vitamina C, unos 30–60 minutos antes de la sesión.",
            timing: "Antes de entrenar.",
            benefits: ["Algunos estudios apuntan a beneficios en tendón y articulación."],
            limits: ["Como proteína para ganar músculo es de baja calidad: no cuenta igual que el whey.",
                     "La evidencia todavía es pequeña."]),

        SupplementInfo("melatonin", "Melatonina", ingredient: "melatonina", evidence: .moderate,
            typicalDose: "0,5–2 mg. Más no es mejor.",
            timing: "30–60 minutos antes de acostarte.",
            benefits: ["Ayuda a adelantar el sueño y con el cambio de horario en viajes."],
            limits: ["No arregla dormir poco por costumbre ni sustituye unos horarios regulares."],
            risks: ["Somnolencia al día siguiente.", "Si tomas medicación o tienes problemas de sueño mantenidos, consúltalo."],
            consultFirst: true),

        SupplementInfo("ashwagandha", "Ashwagandha", ingredient: "ashwagandha", evidence: .limited,
            typicalDose: "300–600 mg al día de extracto estandarizado.",
            timing: "A diario, normalmente por la noche.",
            benefits: ["Algunos estudios ven menos estrés percibido y mejor sueño."],
            limits: ["Los estudios son pequeños y los efectos sobre fuerza o músculo no están claros."],
            risks: ["Puede afectar a la tiroides y al hígado en casos aislados.",
                    "No se recomienda en embarazo, lactancia ni con enfermedad autoinmune o medicación tiroidea."],
            consultFirst: true),

        SupplementInfo("electrolytes", "Sales / electrolitos", ingredient: "electrolitos", evidence: .limited,
            typicalDose: "Según lo que sudes; no hace falta una pauta fija.",
            timing: "En sesiones largas o con mucho calor.",
            benefits: ["Reponer sodio tiene sentido cuando sudas mucho durante mucho tiempo."],
            limits: ["En una sesión normal de gimnasio, con agua y comida normal sobra."]),

        SupplementInfo("multivitamin", "Multivitamínico", ingredient: "multivitamínico", evidence: .insufficient,
            typicalDose: "Una dosis al día según la etiqueta.",
            timing: "Con una comida.",
            benefits: ["Puede cubrir huecos si tu alimentación es muy limitada o estás en déficit fuerte."],
            limits: ["No mejora el rendimiento si ya comes variado.", "No compensa una dieta mal planteada."]),

        SupplementInfo("bcaa", "BCAA (aminoácidos ramificados)", ingredient: "bcaa", evidence: .insufficient,
            typicalDose: "No tiene sentido buscar una dosis si llegas a tu proteína diaria.",
            timing: "—",
            benefits: ["Solo podrían aportar algo con una proteína diaria muy baja, y entonces lo que falta es proteína."],
            limits: ["Con suficiente proteína total no añaden nada medible.",
                     "Un batido de whey ya lleva estos aminoácidos y además los demás."]),

        SupplementInfo("glutamine", "Glutamina", ingredient: "glutamina", evidence: .insufficient,
            typicalDose: "—",
            timing: "—",
            benefits: ["Usos clínicos concretos, fuera del gimnasio."],
            limits: ["No hay base para esperar más músculo, más fuerza ni menos agujetas en personas sanas que entrenan."]),

        SupplementInfo("hmb", "HMB", ingredient: "hmb", evidence: .limited,
            typicalDose: "3 g al día.",
            timing: "Repartido con las comidas.",
            benefits: ["Puede ayudar en personas desentrenadas o en situaciones de pérdida muscular."],
            limits: ["En gente que ya entrena con constancia, los resultados son muy pobres.",
                     "Los estudios más espectaculares no se han podido repetir."]),

        SupplementInfo("zma", "ZMA (zinc, magnesio y B6)", ingredient: "zma", evidence: .insufficient,
            typicalDose: "Según etiqueta.",
            timing: "Por la noche.",
            benefits: ["Si tienes déficit de zinc o magnesio, corregirlo tiene sentido por separado."],
            limits: ["No sube la testosterona si no tienes un déficit.", "Es más barato cubrir cada mineral por su cuenta."],
            risks: ["Exceso de zinc mantenido interfiere con la absorción de cobre."]),
    ]

    static func info(id: String) -> SupplementInfo? { all.first { $0.id == id } }

    static func info(ingredient: String) -> SupplementInfo? {
        let needle = ExerciseCatalog.normalize(ingredient)
        return all.first { ExerciseCatalog.normalize($0.ingredient) == needle }
    }

    static var byEvidence: [EvidenceLevel: [SupplementInfo]] {
        Dictionary(grouping: all, by: \.evidence)
    }
}

// MARK: - Lo que yo tomo

/// Una línea del plan de suplementos del usuario.
struct SupplementPlanItem: Equatable, Identifiable {
    let id: String
    /// Ficha del catálogo, si corresponde a uno conocido.
    var catalogID: String?
    var name: String
    var ingredient: String
    var amountPerDose: Double
    var unit: DoseUnit
    var dosesPerDay: Double
    /// Horas del día a las que se toma (para avisar de la cafeína por la tarde).
    var hours: [Int]
    /// Lo que cuesta el envase y para cuántos días da.
    var packagePrice: Double?
    var packageDays: Int?

    init(id: String = UUID().uuidString, catalogID: String? = nil, name: String, ingredient: String,
         amountPerDose: Double, unit: DoseUnit, dosesPerDay: Double = 1, hours: [Int] = [],
         packagePrice: Double? = nil, packageDays: Int? = nil) {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.ingredient = ingredient
        self.amountPerDose = amountPerDose
        self.unit = unit
        self.dosesPerDay = dosesPerDay
        self.hours = hours
        self.packagePrice = packagePrice
        self.packageDays = packageDays
    }

    var dailyAmount: Double { amountPerDose * dosesPerDay }

    var dailyMilligrams: Double? { unit.milligrams(dailyAmount) }

    /// Coste mensual (30 días). nil si no se sabe el precio o la duración del envase.
    var monthlyCost: Double? {
        guard let packagePrice, let packageDays, packageDays > 0 else { return nil }
        return packagePrice / Double(packageDays) * 30
    }

    var info: SupplementInfo? {
        if let catalogID { return SupplementCatalog.info(id: catalogID) }
        return SupplementCatalog.info(ingredient: ingredient)
    }

    var doseText: String {
        let amount = NumberFormat.oneDecimal(dailyAmount)
        return "\(amount) \(unit.label) al día"
    }
}

enum SupplementChecks {
    /// Tope diario de cafeína que se suele citar como seguro para adultos sanos.
    static let caffeineDailyLimitMg = 400.0
    /// Hora a partir de la cual la cafeína suele estorbar al sueño.
    static let caffeineCutoffHour = 16

    struct Warning: Equatable, Identifiable {
        enum Kind: String { case duplicate, tooMuch, timing, consult, noEvidence }
        let kind: Kind
        let title: String
        let message: String
        var id: String { kind.rawValue + title }
    }

    /// Mismo principio activo en dos productos distintos.
    static func duplicates(_ items: [SupplementPlanItem]) -> [String] {
        var counts: [String: Int] = [:]
        for item in items {
            counts[ExerciseCatalog.normalize(item.ingredient), default: 0] += 1
        }
        return counts.filter { $0.value > 1 }.keys.sorted()
    }

    /// Coste mensual de todo lo que tenga precio. Devuelve además cuántas líneas no lo tienen.
    static func monthlyCost(_ items: [SupplementPlanItem]) -> (total: Double, itemsWithoutPrice: Int) {
        let costs = items.compactMap(\.monthlyCost)
        return (costs.reduce(0, +), items.count - costs.count)
    }

    /// Avisos del plan completo.
    static func warnings(_ items: [SupplementPlanItem]) -> [Warning] {
        var out: [Warning] = []

        for ingredient in duplicates(items) {
            let involved = items.filter { ExerciseCatalog.normalize($0.ingredient) == ingredient }
            out.append(Warning(kind: .duplicate, title: "Lo llevas dos veces: \(ingredient)",
                               message: "\(involved.map(\.name).joined(separator: " y ")) comparten principio activo. "
                               + "Suma las dosis antes de decidir si te hace falta todo."))
        }

        // Cafeína total del día.
        let caffeine = items.filter { ExerciseCatalog.normalize($0.ingredient).contains("cafeina") }
        let caffeineMg = caffeine.compactMap(\.dailyMilligrams).reduce(0, +)
        if caffeineMg > caffeineDailyLimitMg {
            out.append(Warning(kind: .tooMuch, title: "Mucha cafeína al día",
                               message: "Sumas \(NumberFormat.integer(caffeineMg)) mg al día entre lo apuntado. "
                               + "La referencia habitual para adultos sanos son \(NumberFormat.integer(caffeineDailyLimitMg)) mg, "
                               + "y además el café y los refrescos suman por su cuenta."))
        }
        if caffeine.contains(where: { $0.hours.contains { $0 >= caffeineCutoffHour } }) {
            out.append(Warning(kind: .timing, title: "Cafeína por la tarde",
                               message: "Tomada a partir de las \(caffeineCutoffHour):00 suele empeorar el sueño "
                               + "aunque te duermas igual, y dormir mal se nota en el gimnasio al día siguiente."))
        }

        for item in items {
            guard let info = item.info else { continue }
            if info.consultFirst {
                out.append(Warning(kind: .consult, title: "\(info.name): mejor consultarlo",
                                   message: (info.risks.first ?? "") + " " + SupplementCatalog.disclaimer))
            }
            if info.evidence == .insufficient {
                out.append(Warning(kind: .noEvidence, title: "\(info.name): sin evidencia suficiente",
                                   message: (info.limits.first ?? "No hay base para esperar un efecto en el rendimiento.")
                                   + " Ese dinero rinde más en comida y en descanso."))
            }
        }
        return out
    }
}
