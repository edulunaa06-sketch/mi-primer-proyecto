import SwiftUI

/// Botón para abrir Strava y registrar la carrera. Funciona sin OAuth.
struct StravaLaunchButton: View {
    var title = "Abrir Strava y registrar carrera"

    @State private var showNotInstalled = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    switch await StravaLauncher.openRecording() {
                    case .openedRecordLink, .openedApp:
                        resultMessage = "Strava abierto. Pulsa “Grabar”, inicia la actividad y guárdala al terminar."
                    case .notInstalled:
                        showNotInstalled = true
                    }
                }
            } label: {
                Label(title, systemImage: "figure.run")
            }
            .buttonStyle(ActionButtonStyle())

            Text(resultMessage ?? "La carrera se graba y se guarda en Strava. Now or Never no graba GPS.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .alert("Strava no está instalado", isPresented: $showNotInstalled) {
            Button("Abrir App Store") { StravaLauncher.openAppStore() }
            Button("Abrir strava.com") { StravaLauncher.openWebsite() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Instala Strava para registrar tus carreras o abre su web oficial.")
        }
    }
}
