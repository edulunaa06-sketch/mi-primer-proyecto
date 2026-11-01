import Foundation

/// COPIA de `Atlas/Services/WidgetBridge.swift`.
///
/// El widget es otro programa y no comparte código con la app, así que esta estructura está
/// escrita dos veces. Si cambias una, cambia la otra. Si se desincronizan no se rompe nada:
/// el widget no sabrá leer la foto y enseñará el estado vacío.
struct WidgetSnapshot: Codable, Equatable {
    var actualizado: Date
    var kcalComidas: Double
    var kcalObjetivo: Double
    var proteinaG: Double
    var proteinaObjetivoG: Double
    var aguaMl: Int
    var aguaObjetivoMl: Int
    var entrenoNombre: String
    var entrenoTipo: String
    var entrenoHecho: Bool
    var rachaDias: Int
}

enum WidgetBridge {
    static let appGroup = "group.com.example.atlas"
    static let clave = "widget.snapshot"

    /// Devuelve nil si la app se firmó sin el permiso de App Group. El widget lo trata como
    /// «todavía no hay datos» y enseña el estado vacío, nunca falla.
    static func leer() -> WidgetSnapshot? {
        guard let datos = UserDefaults(suiteName: appGroup)?.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: datos)
    }

    /// Lo que se enseña mientras iOS prepara el widget y en la galería de widgets.
    static var ejemplo: WidgetSnapshot {
        WidgetSnapshot(actualizado: Date(),
                       kcalComidas: 1840, kcalObjetivo: 2300,
                       proteinaG: 128, proteinaObjetivoG: 180,
                       aguaMl: 1500, aguaObjetivoMl: 2500,
                       entrenoNombre: "Pierna", entrenoTipo: "strength",
                       entrenoHecho: false, rachaDias: 12)
    }
}

/// Los mismos cuatro estados de calorías que la app, para que el widget no diga otra cosa
/// que la pantalla de Hoy.
enum WidgetEstado {
    case margen, acercandose, enObjetivo, pasado

    static func de(_ kcal: Double, objetivo: Double) -> WidgetEstado {
        guard objetivo > 0 else { return .margen }
        let margen = 100.0
        if kcal > objetivo + margen { return .pasado }
        if kcal >= objetivo - margen { return .enObjetivo }
        if kcal >= objetivo * 0.75 { return .acercandose }
        return .margen
    }

    var texto: String {
        switch self {
        case .margen: return "Te queda margen"
        case .acercandose: return "Te acercas al objetivo"
        case .enObjetivo: return "En el objetivo"
        case .pasado: return "Te has pasado"
        }
    }
}
