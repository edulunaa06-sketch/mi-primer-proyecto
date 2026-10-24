import SwiftData
import SwiftUI

/// Strava: conectar tu cuenta (sin servidor, directamente desde el iPhone) e importar tus carreras.
/// Necesita una «aplicación de API» propia en strava.com/settings/api (gratis, 2 minutos): la guía lo explica.
struct StravaSection: View {
    @Environment(StravaService.self) private var strava
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var clientID = ""
    @State private var secret = ""
    @State private var message: String?
    @State private var showGuide = false

    var body: some View {
        Section {
            switch strava.status {
            case .connected:
                Label("Conectado", systemImage: "checkmark.seal.fill").foregroundStyle(DS.good)
                Button {
                    Task {
                        let n = await strava.syncRuns(into: context)
                        message = strava.lastError ?? "Importadas \(n) carreras."
                    }
                } label: { Label(strava.isWorking ? "Importando…" : "Importar carreras ahora", systemImage: "arrow.down.circle") }
                .disabled(strava.isWorking)
                if let last = strava.lastSync {
                    Text("Última importación: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(DS.text3)
                }
                Button("Desconectar", role: .destructive) { Task { await strava.disconnect() } }
            case .disconnected:
                Button {
                    if let url = strava.makeAuthorizationURL() { openURL(url) }
                } label: { Label("Conectar con Strava", systemImage: "link") }
                Button("Cambiar ID o secreto", role: .destructive) { Task { await strava.forgetCredentials() } }
            case .notConfigured:
                TextField("ID de cliente (número)", text: $clientID)
                    .keyboardType(.numberPad)
                SecureField("Secreto de cliente", text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    if let error = strava.saveCredentials(clientID: clientID, clientSecret: secret) {
                        message = error
                    } else {
                        secret = ""
                        message = nil
                        if let url = strava.makeAuthorizationURL() { openURL(url) }
                    }
                } label: { Label("Guardar y conectar", systemImage: "link") }
                .disabled(clientID.isEmpty)
            }
            Button { showGuide = true } label: { Label("Cómo conectar Strava (paso a paso)", systemImage: "questionmark.circle") }
            if let message = message ?? strava.lastError {
                Text(message).font(.caption).foregroundStyle(DS.warn)
            }
        } header: { Text("Strava") } footer: {
            Text("Tus carreras de Strava aparecen solas en Entrenar y en Progreso › Carrera (se importan al abrir la app). El secreto se guarda en el Llavero del iPhone.")
        }
        .onAppear { clientID = strava.clientID }
        .sheet(isPresented: $showGuide) { StravaGuide() }
    }
}

struct StravaGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Conectar Strava").font(.display(24))
                    Text("Strava solo deja leer tus actividades a «aplicaciones de API». Creas la tuya una vez (gratis) y ATLAS se conecta directamente, sin servidores.")
                        .font(.footnote).foregroundStyle(DS.text2)
                    step(1, "Abre strava.com/settings/api en el navegador e inicia sesión.")
                    Button { openURL(StravaAPI.apiSettingsURL) } label: { Label("Abrir la página de Strava", systemImage: "safari") }
                        .buttonStyle(.secondary)
                    step(2, "Rellena: Nombre de la aplicación «ATLAS», Categoría «Visualizer», Sitio web «https://localhost» y, MUY IMPORTANTE, Dominio de devolución de llamada (Authorization Callback Domain): «localhost».")
                    step(3, "Acepta y crea. Strava te enseña el «ID de cliente» (un número) y el «Secreto de cliente» (pulsa «mostrar» y cópialo entero).")
                    step(4, "En ATLAS: Perfil › Strava, pega el ID y el secreto y pulsa «Guardar y conectar». Autoriza en Strava marcando leer tus actividades.")
                    step(5, "¡Listo! Tus carreras se importan solas cada vez que abres la app.")
                }
                .padding(20)
            }
            .background(AtlasBackground())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 14, weight: .heavy)).frame(width: 28, height: 28)
                .background(Circle().fill(DS.brandDiagonal))
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        }
        .glass(padding: 12, radius: 16)
    }
}
