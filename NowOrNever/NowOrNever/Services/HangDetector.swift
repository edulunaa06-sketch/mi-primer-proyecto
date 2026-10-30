import Foundation

/// Detector de bloqueos: un vigilante en segundo plano comprueba 4 veces por segundo que la pantalla
/// responde. Si se queda congelada más de 0,7 s, apunta cuánto duró y en qué pantalla estabas.
/// Se ve en Ajustes › Diagnóstico de fluidez (solo en este iPhone; no se envía a ningún sitio).
final class HangDetector: @unchecked Sendable {
    static let shared = HangDetector()

    struct Hang: Codable, Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let seconds: Double
        let screen: String
    }

    private static let storageKey = "diagnostics.hangs"
    private static let threshold: TimeInterval = 0.7
    private let lock = NSLock()
    private var lastPong = Date()
    private var hangStart: Date?
    private var screenName = "Inicio"
    private var started = false
    private var paused = false

    /// Pantalla actual (la ponen las vistas al aparecer).
    var screen: String {
        get { lock.lock(); defer { lock.unlock() }; return screenName }
        set { lock.lock(); screenName = newValue; lock.unlock() }
    }

    /// En segundo plano iOS congela la app a propósito: eso no es un bloqueo.
    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        hangStart = nil
        lastPong = Date()
        lock.unlock()
    }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lastPong = Date()
        lock.unlock()
        let thread = Thread { [weak self] in self?.watch() }
        thread.name = "NowOrNever.HangDetector"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func watch() {
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.lastPong = Date()
                let start = self.hangStart
                self.hangStart = nil
                let screen = self.screenName
                let paused = self.paused
                self.lock.unlock()
                // Al volver a responder se guarda el bloqueo con su duración real.
                if let start, !paused {
                    let seconds = Date().timeIntervalSince(start) + Self.threshold
                    Self.record(Hang(date: start, seconds: seconds, screen: screen))
                }
            }
            lock.lock()
            if paused { lastPong = Date() }
            if !paused, hangStart == nil, Date().timeIntervalSince(lastPong) > Self.threshold + 0.25 {
                hangStart = Date()
            }
            lock.unlock()
        }
    }

    static func record(_ hang: Hang) {
        var list = all()
        list.insert(hang, at: 0)
        if list.count > 30 { list.removeLast(list.count - 30) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    static func all() -> [Hang] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([Hang].self, from: data) else { return [] }
        return list
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: storageKey) }
}
