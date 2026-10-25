import Foundation

/// Formato del archivo de copia de seguridad (JSON). Contiene TODOS los datos de la app,
/// incluidas las fotos de progreso. No incluye la clave de Claude ni los tokens de Strava (Llavero).
struct BackupFile: Codable, Equatable {
    static let currentFormat = 1
    static let appIdentifier = "Atlas"

    var app: String = BackupFile.appIdentifier
    var format: Int = BackupFile.currentFormat
    var createdAt: Date
    var appVersion: String

    var settings: Settings
    var weights: [Weight] = []
    var routine: [RoutineExercise] = []
    var sessionTitles: [SessionTitle] = []
    var sessionLogs: [SessionLog] = []
    var foods: [Food] = []
    var plans: [Plan] = []
    var mealRecords: [MealRecord] = []
    var daySelections: [DaySelection] = []
    var dayChoices: [DayChoice] = []
    var customItems: [CustomItem] = []
    var photos: [Photo] = []
    var runs: [Run] = []
    var dailySteps: [DaySteps] = []
    var dayMarks: [DayMarkEntry] = []

    struct Settings: Codable, Equatable {
        var kcalTarget: Double
        var proteinTarget: Double
        var carbsTarget: Double
        var fatTarget: Double
        var stepGoal: Int
        var trackingStartDate: Date?
        var onboardingCompleted: Bool
        var creatineReminderEnabled: Bool
        var creatineHour: Int
        var creatineMinute: Int
        var photoReminderEnabled: Bool
        var photoReminderHour: Int
        var defaultPlanID: UUID?
        var stravaClientID: String
        var stravaBackendURL: String
        var heightCm: Double?
        var age: Int?
        var sexRaw: String?
        var activityRaw: String
        var goalRaw: String
        var autoTargets: Bool
        var stepGoalAdaptive: Bool
        var stepGoalAdjustedDayKey: String
        var stepReminderEnabled: Bool
        var stepReminderFromMinutes: Int
        var stepReminderToMinutes: Int
        var weightReminderEnabled: Bool
        var weightReminderFromMinutes: Int
        var weightReminderToMinutes: Int
        /// Margen (± kcal) del objetivo calórico. Opcional: las copias antiguas no lo traen.
        var kcalMargin: Double? = nil
    }

    struct Weight: Codable, Equatable {
        var id: UUID
        var date: Date
        var weightKg: Double
        var waistCm: Double?
        var note: String
    }

    struct RoutineExercise: Codable, Equatable {
        var exerciseID: String
        var sessionID: String
        var name: String
        var sets: Int
        var repMin: Int
        var repMax: Int
        var order: Int
    }

    struct SessionTitle: Codable, Equatable {
        var sessionID: String
        var title: String
    }

    struct SessionLog: Codable, Equatable {
        var weekStart: Date
        var sessionID: String
        var isCompleted: Bool
        var completedAt: Date?
        var notes: String
        var lastModified: Date
        var exercises: [ExerciseLog]
    }

    struct ExerciseLog: Codable, Equatable {
        var exerciseID: String
        var order: Int
        var isCompleted: Bool
        var name: String
        var targetSets: Int
        var repRange: String
    }

    struct Food: Codable, Equatable {
        var id: UUID
        var seedKey: String
        var name: String
        var kcalPer100: Double
        var proteinPer100: Double
        var carbsPer100: Double
        var fatPer100: Double
        var macrosKnown: Bool
        var basisRaw: String
        var isProvisional: Bool
        var isUserEdited: Bool
        var sourceNote: String
    }

    struct Plan: Codable, Equatable {
        var id: UUID
        var number: Int
        var name: String
        var note: String
        var isExample: Bool
        var isLibrary: Bool
        var meals: [Meal]
    }

    struct Meal: Codable, Equatable {
        var mealTypeRaw: String
        var items: [MealItem]
    }

    struct MealItem: Codable, Equatable {
        var grams: Double
        var order: Int
        var foodID: UUID?
    }

    struct MealRecord: Codable, Equatable {
        var dayKey: String
        var date: Date
        var mealTypeRaw: String
        var planName: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var completedAt: Date
    }

    struct DaySelection: Codable, Equatable {
        var dayKey: String
        var planID: UUID
    }

    struct DayChoice: Codable, Equatable {
        var dayKey: String
        var mealTypeRaw: String
        var planID: UUID
        var factor: Double
        /// nil en copias antiguas: se trata como cambiada por ti.
        var isUserChoice: Bool?
    }

    struct CustomItem: Codable, Equatable {
        var dayKey: String
        var mealTypeRaw: String
        var name: String
        var grams: Double
        var kcalPer100: Double
        var proteinPer100: Double
        var carbsPer100: Double
        var fatPer100: Double
        var sourceRaw: String
        var order: Int
        var createdAt: Date
    }

    struct Photo: Codable, Equatable {
        var year: Int
        var month: Int
        var viewRaw: String
        var fileName: String
        var createdAt: Date
        var updatedAt: Date
        /// JPEG de la foto (en el JSON va en base64). nil si el archivo no se pudo leer.
        var imageData: Data?
    }

    struct Run: Codable, Equatable {
        var stravaID: Int64
        var name: String
        var sportType: String
        var startDate: Date
        var distanceMeters: Double
        var movingTimeSeconds: Int
        var elapsedTimeSeconds: Int
        var elevationGainMeters: Double?
        var importedAt: Date
    }

    struct DaySteps: Codable, Equatable {
        var dayKey: String
        var date: Date
        var steps: Int
        var goal: Int
    }

    struct DayMarkEntry: Codable, Equatable {
        var dayKey: String
        var date: Date
        var markRaw: String
    }

    // MARK: Lectura y escritura

    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case newerFormat(Int)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notABackup: return "Este archivo no es una copia de seguridad de ATLAS."
            case .newerFormat(let v): return "La copia es de una versión más nueva de la app (formato \(v)). Actualiza la app para importarla."
            case .unreadable(let detail): return "No se pudo leer la copia: \(detail)"
            }
        }
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    func encoded() throws -> Data { try Self.encoder().encode(self) }

    static func decode(_ data: Data) throws -> BackupFile {
        struct Header: Decodable {
            var app: String?
            var format: Int?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let header = try? decoder.decode(Header.self, from: data), header.app == appIdentifier, let format = header.format else {
            throw BackupError.notABackup
        }
        guard format <= currentFormat else { throw BackupError.newerFormat(format) }
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable(error.localizedDescription)
        }
    }

    /// Resumen legible para confirmar antes de importar.
    var summary: String {
        var parts = ["\(weights.count) pesajes", "\(sessionLogs.filter(\.isCompleted).count) sesiones completadas",
                     "\(mealRecords.count) comidas registradas", "\(photos.count) fotos"]
        if !runs.isEmpty { parts.append("\(runs.count) carreras") }
        if !dailySteps.isEmpty { parts.append("\(dailySteps.count) días de pasos") }
        if !dayMarks.isEmpty { parts.append("\(dayMarks.count) días marcados") }
        return parts.joined(separator: ", ")
    }

    static func suggestedFileName(for date: Date) -> String {
        "Atlas-copia-\(DateUtils.dayKey(date)).json"
    }
}
