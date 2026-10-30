import Foundation

/// Frases motivadoras (gimnasio y desarrollo personal) que aparecen al abrir la app.
/// Sin autores inventados: solo se cita a alguien cuando la atribución es conocida.
enum Motivation {
    struct Quote: Equatable {
        let text: String
        let author: String?
    }

    static let quotes: [Quote] = [
        Quote(text: "Ahora o nunca. El entreno de hoy no se recupera mañana.", author: nil),
        Quote(text: "La disciplina es elegir entre lo que quieres ahora y lo que más quieres.", author: nil),
        Quote(text: "No tienes que tener ganas. Tienes que empezar.", author: nil),
        Quote(text: "Cada repetición cuenta, sobre todo la que no te apetece hacer.", author: nil),
        Quote(text: "El cuerpo consigue lo que la mente se cree.", author: nil),
        Quote(text: "Un 1 % mejor cada día. En un año no te vas a reconocer.", author: nil),
        Quote(text: "La motivación te hace empezar. El hábito te hace seguir.", author: nil),
        Quote(text: "No cuentes los días: haz que los días cuenten.", author: "Muhammad Ali"),
        Quote(text: "Somos lo que hacemos repetidamente. La excelencia no es un acto, es un hábito.", author: "Will Durant"),
        Quote(text: "El dolor de la disciplina pesa gramos. El del arrepentimiento pesa toneladas.", author: nil),
        Quote(text: "Hoy es un buen día para ser mejor que ayer.", author: nil),
        Quote(text: "Las excusas no queman calorías.", author: nil),
        Quote(text: "El progreso lento sigue siendo progreso.", author: nil),
        Quote(text: "No pares cuando estés cansado. Para cuando hayas terminado.", author: nil),
        Quote(text: "Tu única competencia es la persona que eras ayer.", author: nil),
        Quote(text: "Lo difícil de hoy será tu calentamiento de mañana.", author: nil),
        Quote(text: "Constancia antes que intensidad. Siempre.", author: nil),
        Quote(text: "El éxito es la suma de pequeños esfuerzos repetidos día tras día.", author: "Robert Collier"),
        Quote(text: "Entrena en silencio. Que hablen los resultados.", author: nil),
        Quote(text: "Si no te reta, no te cambia.", author: nil),
        Quote(text: "Nadie se arrepiente de un entreno hecho.", author: nil),
        Quote(text: "No busques tiempo: créalo.", author: nil),
        Quote(text: "La comida es combustible. Elige bien lo que le echas al motor.", author: nil),
        Quote(text: "Duerme, come, entrena, repite. Lo básico bien hecho gana.", author: nil),
        Quote(text: "Tus hábitos de hoy son tu cuerpo de dentro de seis meses.", author: nil),
        Quote(text: "Cae siete veces, levántate ocho.", author: "Proverbio japonés"),
        Quote(text: "El mejor momento para empezar fue ayer. El segundo mejor es ahora.", author: "Proverbio"),
        Quote(text: "Ser fuerte no es no caer, es levantarse cada vez.", author: nil),
        Quote(text: "Hazlo con miedo, pero hazlo.", author: nil),
        Quote(text: "La comodidad no construye músculo.", author: nil),
        Quote(text: "Quien quiere hacer algo encuentra un medio; quien no, una excusa.", author: "Proverbio"),
        Quote(text: "Cumple contigo igual que cumples con los demás.", author: nil),
        Quote(text: "Paso a paso se llega lejos. Literalmente: hoy, a por tus pasos.", author: nil),
        Quote(text: "No te compares. Compárate con tu foto del mes pasado.", author: nil),
        Quote(text: "Un mal día de entreno es mejor que ningún día de entreno.", author: nil),
        Quote(text: "La fuerza no viene de lo que puedes hacer, sino de superar lo que creías que no podías.", author: nil),
        Quote(text: "Hoy pesa la barra. Mañana pesará menos.", author: nil),
        Quote(text: "La versión de ti que quieres ser ya está esperando. Ve a buscarla.", author: nil),
        Quote(text: "Ganar empieza por presentarse.", author: nil),
        Quote(text: "Tu cuerpo puede casi con todo. Es a tu mente a la que hay que convencer.", author: nil),
    ]

    /// Una frase distinta de la última que se mostró.
    static func next(after lastIndex: Int?, random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Int {
        guard quotes.count > 1 else { return 0 }
        var index = random(quotes.count)
        if index == lastIndex { index = (index + 1) % quotes.count }
        return index
    }
}

/// Estimaciones a partir de los pasos (aproximadas: zancada media de 0,76 m y unas 0,04 kcal por paso).
enum StepEstimates {
    static let strideMeters = 0.76
    static let kcalPerStep = 0.04

    static func kilometers(_ steps: Int) -> Double { Double(steps) * strideMeters / 1000 }
    static func kcal(_ steps: Int) -> Double { Double(steps) * kcalPerStep }
    static func fraction(_ steps: Int, goal: Int) -> Double { goal > 0 ? min(Double(steps) / Double(goal), 1) : 0 }
}
