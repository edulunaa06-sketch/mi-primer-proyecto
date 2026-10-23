import SwiftUI
import UIKit

/// Guía paso a paso (sin programar nada) para que la app pueda importar tus carreras de Strava.
struct StravaSetupGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner(text: "Strava solo deja leer tus carreras a apps que tú mismo autorizas. Para eso creas una «aplicación de API» con tu cuenta, gratis, una sola vez. No hace falta saber programar ni ningún servidor.",
                           symbol: "info.circle.fill", color: Theme.lime)

                step(1, "Abre la página de Strava",
                     "Pulsa el botón e inicia sesión con tu cuenta de Strava si te lo pide.") {
                    Button {
                        UIApplication.shared.open(StravaAPI.apiSettingsURL)
                    } label: {
                        Label("Abrir strava.com/settings/api", systemImage: "safari")
                    }
                    .buttonStyle(LimeButtonStyle(filled: false))
                }

                step(2, "Rellena el formulario así", nil) {
                    VStack(alignment: .leading, spacing: 8) {
                        field("Nombre de la aplicación (Application Name)", "Now or Never")
                        field("Categoría (Category)", "Training (o cualquiera)")
                        field("Club", "Déjalo vacío")
                        field("Sitio web (Website)", "http://localhost")
                        field("Descripción (Application Description)", "Uso personal")
                        field("Dominio de devolución de llamada (Authorization Callback Domain)", "localhost", important: true)
                        Text("Marca la casilla de aceptar las condiciones y pulsa Crear. Si te pide un icono, sube cualquier foto.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }

                step(3, "Copia los dos datos",
                     "En esa misma página aparecen «ID de cliente» (Client ID, un número) y «Secreto de cliente» (Client Secret; pulsa «mostrar» para verlo). Mantén pulsado cada uno para copiarlo.") {
                    EmptyView()
                }

                step(4, "Pégalos en la app",
                     "Vuelve a Ajustes › Strava, pega el ID y el secreto y pulsa «Guardar y conectar con Strava». Se abrirá Strava: pulsa Autorizar. Listo: tus carreras se importan y, a partir de ahí, se actualizan solas cada vez que abres la app.") {
                    EmptyView()
                }

                InfoBanner(text: "El secreto se guarda solo en el Llavero de este iPhone y no va en la copia de seguridad. Si reinstalas la app desde cero tendrás que volver a pegarlo (el ID y el secreto siguen en la misma página de Strava).",
                           symbol: "lock.fill", color: Theme.textSecondary)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Configurar Strava")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step<Content: View>(_ n: Int, _ title: String, _ text: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(n)")
                    .font(.caption.weight(.heavy))
                    .frame(width: 26, height: 26)
                    .background(Theme.lime, in: Circle())
                    .foregroundStyle(Theme.onLime)
                Text(title).font(.headline)
            }
            if let text {
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .card()
    }

    private func field(_ name: String, _ value: String, important: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(Theme.textTertiary)
            HStack {
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(important ? Theme.lime : Theme.textPrimary)
                    .textSelection(.enabled)
                if important {
                    Text("IMPORTANTE").font(.caption2.weight(.heavy)).foregroundStyle(Theme.onLime)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.lime, in: Capsule())
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
