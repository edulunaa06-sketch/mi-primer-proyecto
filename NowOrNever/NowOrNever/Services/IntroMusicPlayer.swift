import AVFoundation
import Foundation

/// Música de la intro (pista original incluida en la app, `IntroMusic.m4a`).
/// Suena solo durante la pantalla de carga y la frase; al entrar al menú se apaga con un fundido.
@MainActor
final class IntroMusicPlayer {
    static let shared = IntroMusicPlayer()
    static let enabledKey = "intro.musicEnabled"

    private var player: AVAudioPlayer?

    /// Activada por defecto; se puede quitar en Ajustes.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func play() {
        guard Self.isEnabled, player == nil,
              let url = Bundle.main.url(forResource: "IntroMusic", withExtension: "m4a") else { return }
        do {
            // Suena aunque el iPhone esté en silencio (es lo que pediste al abrir la app) y baja
            // el volumen de otra música mientras dura; se puede desactivar en Ajustes.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.85
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    /// Fundido de medio segundo y silencio; devuelve el audio a otras apps.
    func stop() {
        guard let player else { return }
        self.player = nil
        player.setVolume(0, fadeDuration: 0.5)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            player.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
