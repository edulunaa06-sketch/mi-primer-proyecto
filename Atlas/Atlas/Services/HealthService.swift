import Foundation
import HealthKit
import Observation

/// Puente con Apple Salud.
///
/// Qué va en cada dirección:
///  · Pasos: se LEEN de Salud. El iPhone solo guarda 7 días en el sensor de movimiento;
///    Salud guarda todo el historial, así que conectado se rellenan los días de atrás.
///  · Peso: en los DOS sentidos. Lo que te pesas en la app va a Salud, y lo que te pesa
///    una báscula conectada entra en la app.
///  · Entrenos, agua y comida: se ESCRIBEN en Salud.
///
/// Reglas de la casa:
///  · Es opcional y hay que conectarlo a mano. Sin conectar, la app funciona igual que
///    siempre: el sensor de movimiento del iPhone para los pasos y nada sale del móvil.
///  · Si la firma de la app no trae el permiso de Salud, `connect()` falla con un motivo
///    legible y la app sigue funcionando. No se rompe nada.
///  · Al leer peso se descartan las muestras que escribió esta misma app, o se reimportaría
///    en bucle lo que acaba de salir.
///  · Nunca se pisa un pesaje que ya tengas: de Salud solo entran los días en los que no
///    te habías pesado en la app.
///  · El agua y la comida del día se guardan como UNA muestra que se reemplaza al cambiar,
///    en vez de ir sumando muestras, para que el total de Salud no se dispare.
@MainActor
@Observable
final class HealthService {
    enum State: Equatable {
        /// El dispositivo no tiene Apple Salud.
        case unavailable
        /// Disponible, pero todavía no lo has conectado.
        case off
        /// Conectado: se pidieron los permisos.
        case on
        /// Se intentó conectar y no se pudo. Lleva el motivo en cristiano.
        case failed(String)
    }

    private let store = HKHealthStore()
    private(set) var state: State
    /// Qué pasó en la última sincronización, para enseñarlo en Ajustes.
    private(set) var lastSummary: String?

    private static let connectedKey = "health.connected"

    // MARK: Tipos

    private static let steps = HKQuantityType(.stepCount)
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let water = HKQuantityType(.dietaryWater)
    private static let energy = HKQuantityType(.dietaryEnergyConsumed)
    private static let protein = HKQuantityType(.dietaryProtein)
    private static let carbs = HKQuantityType(.dietaryCarbohydrates)
    private static let fat = HKQuantityType(.dietaryFatTotal)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)

    private static let readTypes: Set<HKObjectType> = [steps, bodyMass]
    private static let writeTypes: Set<HKSampleType> = [
        bodyMass, water, energy, protein, carbs, fat, activeEnergy, HKObjectType.workoutType(),
    ]

    init() {
        if !HKHealthStore.isHealthDataAvailable() {
            state = .unavailable
        } else if UserDefaults.standard.bool(forKey: Self.connectedKey) {
            state = .on
        } else {
            state = .off
        }
    }

    var isOn: Bool { state == .on }

    // MARK: Conectar

    /// Pide los permisos. Es la única puerta de entrada: hasta que no se llama, la app no
    /// toca Salud para nada.
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            state = .on
        } catch {
            state = .failed(Self.explain(error))
        }
    }

    /// Deja de usar Salud. No borra nada de lo ya escrito: eso se quita desde la app Salud,
    /// que es donde el usuario manda sobre sus datos.
    func disconnect() {
        UserDefaults.standard.set(false, forKey: Self.connectedKey)
        state = .off
        lastSummary = nil
    }

    /// Traduce el fallo de iOS a algo que se pueda leer.
    private static func explain(_ error: Error) -> String {
        let text = error.localizedDescription
        let code = (error as NSError).code
        // El caso que de verdad puede pasar aquí: la app se firmó sin el permiso de Salud.
        if code == HKError.errorAuthorizationDenied.rawValue || text.lowercased().contains("entitlement") {
            return "iOS no ha dejado pedir el permiso de Salud. Suele pasar cuando la app se ha "
                + "firmado sin ese permiso. La app sigue funcionando igual sin Salud."
        }
        return text
    }

    // MARK: Leer

    /// Pasos por día de los últimos `days` días, del más antiguo al más reciente.
    /// Los días sin datos no se devuelven (no se inventa un cero).
    func dailySteps(days: Int = 30, now: Date = Date()) async -> [(date: Date, steps: Int)] {
        guard isOn else { return [] }
        let today = DateUtils.startOfDay(now)
        guard let start = DateUtils.calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: Self.steps,
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var out: [(date: Date, steps: Int)] = []
                results?.enumerateStatistics(from: start, to: now) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    let value = Int(sum.doubleValue(for: .count()).rounded())
                    if value > 0 { out.append((date: statistics.startDate, steps: value)) }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Pesajes de Salud desde `since`, SIN los que escribió esta app (o se reimportarían
    /// en bucle los que la propia app acaba de mandar).
    func weightsFromOtherApps(since: Date) async -> [(date: Date, kg: Double)] {
        guard isOn else { return [] }
        let range = HKQuery.predicateForSamples(withStart: since, end: Date())
        let notMine = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default()))
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [range, notMine])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: Self.bodyMass, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                         ascending: true)]) { _, samples, _ in
                let out = (samples as? [HKQuantitySample] ?? []).map {
                    (date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// De los pesajes que hay en Salud, cuáles merece la pena traerse: solo los de días en
    /// los que no te habías pesado en la app. Así nunca se pisa lo que tú has apuntado.
    ///
    /// Está aparte y sin HealthKit a propósito: así se puede probar sin un iPhone de verdad.
    nonisolated static func weightsToImport(_ health: [(date: Date, kg: Double)],
                                            existingDayKeys: Set<String>) -> [(date: Date, kg: Double)] {
        var taken = existingDayKeys
        var out: [(date: Date, kg: Double)] = []
        // Ordenados por fecha: si Salud trae dos del mismo día, se queda el primero.
        for entry in health.sorted(by: { $0.date < $1.date }) where entry.kg > 0 {
            let key = DateUtils.dayKey(entry.date)
            guard !taken.contains(key) else { continue }
            taken.insert(key)
            out.append(entry)
        }
        return out
    }

    // MARK: Escribir

    func saveWeight(kg: Double, date: Date) async {
        guard isOn, kg > 0 else { return }
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: Self.bodyMass, quantity: quantity, start: date, end: date)
        try? await store.save(sample)
    }

    /// El agua de un día entero. Reemplaza lo que esta app hubiera escrito ese día en vez de
    /// sumar otra muestra, porque el contador de la app sube y baja.
    func setWater(totalMl: Int, on date: Date) async {
        guard isOn else { return }
        await replaceOwnSamples(of: Self.water, on: date) {
            guard totalMl > 0 else { return nil }
            let quantity = HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(totalMl))
            return [HKQuantitySample(type: Self.water, quantity: quantity,
                                     start: DateUtils.startOfDay(date), end: date)]
        }
    }

    /// Lo comido en un día: calorías y macros. Igual que el agua, se reemplaza el total del
    /// día en lugar de ir añadiendo, para que no se dispare si cambias una comida.
    func setNutrition(kcal: Double, proteinG: Double, carbsG: Double, fatG: Double, on date: Date) async {
        guard isOn else { return }
        let start = DateUtils.startOfDay(date)
        let pairs: [(HKQuantityType, HKUnit, Double)] = [
            (Self.energy, .kilocalorie(), kcal),
            (Self.protein, .gram(), proteinG),
            (Self.carbs, .gram(), carbsG),
            (Self.fat, .gram(), fatG),
        ]
        for (type, unit, value) in pairs {
            await replaceOwnSamples(of: type, on: date) {
                guard value > 0 else { return nil }
                return [HKQuantitySample(type: type,
                                         quantity: HKQuantity(unit: unit, doubleValue: value),
                                         start: start, end: date)]
            }
        }
    }

    enum WorkoutKind {
        case strength
        case run

        var activityType: HKWorkoutActivityType {
            switch self {
            case .strength: return .traditionalStrengthTraining
            case .run: return .running
            }
        }
    }

    /// Manda un entreno terminado a Salud, para que cuente en Forma física.
    func saveWorkout(_ kind: WorkoutKind, start: Date, end: Date, kcal: Double?) async {
        guard isOn, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = kind.activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let kcal, kcal > 0 {
                let sample = HKQuantitySample(type: Self.activeEnergy,
                                              quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                              start: start, end: end)
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Que no se pueda escribir en Salud no puede romper el guardado del entreno,
            // que ya está a salvo en la app.
            lastSummary = "No se pudo guardar el entreno en Salud: \(error.localizedDescription)"
        }
    }

    /// Borra lo que ESTA app escribió de ese tipo ese día y guarda lo nuevo.
    /// Solo toca muestras propias: lo que hayan escrito otras apps no se toca jamás.
    private func replaceOwnSamples(of type: HKQuantityType, on date: Date,
                                   build: () -> [HKQuantitySample]?) async {
        let start = DateUtils.startOfDay(date)
        guard let end = DateUtils.calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [range, mine])
        let existing: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
        if !existing.isEmpty { try? await store.delete(existing) }
        if let fresh = build(), !fresh.isEmpty { try? await store.save(fresh) }
    }
}
