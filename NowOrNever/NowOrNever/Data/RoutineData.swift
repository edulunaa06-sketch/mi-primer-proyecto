import Foundation

/// La rutina semanal que viene cargada de fábrica.
/// Después se puede editar entera desde la pestaña Entreno.
enum RoutineData {

    /// Descanso largo para los básicos pesados, corto para el resto.
    static let longRest = 150   // 2:30 min
    static let shortRest = 90   // 1:30 min

    /// Ejercicios que piden 2-3 min de descanso.
    private static let heavyExercises: Set<String> = [
        "Press banca",
        "Press inclinado con mancuernas",
        "Hack squat",
        "Peso muerto rumano",
        "Remo sentado en máquina o polea agarre ancho",
        "Remo sentado en polea"
    ]

    static func restSeconds(for exercise: String) -> Int {
        heavyExercises.contains(exercise) ? longRest : shortRest
    }

    /// Plantilla de un día, antes de convertirse en modelos de SwiftData.
    struct DayTemplate {
        let weekday: Int
        let name: String
        let kind: WorkoutKind
        let note: String
        /// (nombre, series, repsMin, repsMax)
        let exercises: [(String, Int, Int, Int)]
    }

    static let week: [DayTemplate] = [
        DayTemplate(weekday: 1, name: "Carrera suave", kind: .cardio,
                    note: "Carrera suave, sin pesas.",
                    exercises: []),

        DayTemplate(weekday: 2, name: "Push", kind: .strength, note: "", exercises: [
            ("Press banca", 3, 8, 10),
            ("Press de hombros en máquina", 3, 10, 12),
            ("Aperturas en peck-deck", 3, 15, 20),
            ("Elevación lateral en polea", 3, 10, 15),
            ("Extensión de tríceps por encima de la cabeza en polea", 3, 8, 12),
            ("Patada de tríceps en polea", 3, 10, 15)
        ]),

        DayTemplate(weekday: 3, name: "Pull", kind: .strength, note: "", exercises: [
            ("Jalón al pecho agarre prono", 3, 8, 12),
            ("Remo sentado en máquina o polea agarre ancho", 3, 8, 12),
            ("Pullover en polea", 2, 10, 15),
            ("Peck-deck inverso", 3, 12, 20),
            ("Curl inclinado con mancuernas", 3, 8, 12),
            ("Curl martillo con cuerda", 2, 10, 15)
        ]),

        DayTemplate(weekday: 4, name: "Piernas", kind: .strength, note: "", exercises: [
            ("Hack squat", 3, 6, 10),
            ("Peso muerto rumano", 3, 6, 10),
            ("Prensa de piernas", 2, 10, 15),
            ("Curl femoral sentado", 3, 8, 12),
            ("Extensión de cuádriceps", 2, 10, 15),
            ("Gemelos en máquina", 3, 10, 15),
            ("Crunch abdominal en polea", 3, 10, 15)
        ]),

        DayTemplate(weekday: 5, name: "Descanso", kind: .rest,
                    note: "Día libre. Descansa y come bien.",
                    exercises: []),

        DayTemplate(weekday: 6, name: "Pecho + espalda", kind: .strengthCardio,
                    note: "Al terminar, carrera suave de 20-30 min.",
                    exercises: [
                        ("Press inclinado con mancuernas", 3, 8, 12),
                        ("Jalón al pecho agarre neutro", 3, 8, 12),
                        ("Press de pecho en máquina", 2, 8, 12),
                        ("Remo sentado en polea", 3, 8, 12),
                        ("Aperturas de pecho en polea", 2, 10, 15),
                        ("Pullover en polea", 2, 10, 15)
                    ]),

        DayTemplate(weekday: 7, name: "Hombros y brazos", kind: .strength, note: "", exercises: [
            ("Elevación lateral en polea", 3, 12, 20),
            ("Peck-deck inverso", 2, 12, 20),
            ("Curl predicador en máquina", 3, 8, 12),
            ("Extensión de tríceps por encima de la cabeza", 2, 10, 15),
            ("Curl inclinado con mancuernas", 2, 10, 15),
            ("Extensión de tríceps con cuerda", 2, 10, 15),
            ("Curl inverso con barra EZ", 2, 12, 15),
            ("Curl de muñeca", 2, 12, 20)
        ])
    ]

    /// Crea los modelos de SwiftData de toda la semana.
    static func makeWeek() -> [WorkoutDayPlan] {
        week.map { template in
            let day = WorkoutDayPlan(weekday: template.weekday,
                                     name: template.name,
                                     kind: template.kind,
                                     note: template.note)
            day.exercises = template.exercises.enumerated().map { index, item in
                ExercisePlan(name: item.0,
                             sets: item.1,
                             repsMin: item.2,
                             repsMax: item.3,
                             restSeconds: restSeconds(for: item.0),
                             order: index)
            }
            return day
        }
    }
}
