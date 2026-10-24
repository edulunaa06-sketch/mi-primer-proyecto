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

/// Recordatorios diarios que puedes encender y poner a tu hora.
struct RemindersSection: View {
    @Bindable var profile: Profile

    var body: some View {
        Section {
            row(.weighIn, "Pesarme", "scalemass", \.remindWeighIn, defaultMinutes: 7 * 60 + 30)
            row(.dinner, "Apuntar la cena", "fork.knife", \.remindDinner, defaultMinutes: 21 * 60 + 30)
            row(.workout, "Entrenar", "dumbbell", \.remindWorkout, defaultMinutes: 18 * 60)
            row(.creatine, "Creatina", "pills", \.remindCreatine, defaultMinutes: 9 * 60)
        } header: { Text("Recordatorios") } footer: {
            Text("Los hábitos se construyen con recordatorios. Se repiten cada día a la hora que elijas.")
        }
    }

    private func row(_ kind: Reminders.Kind, _ title: String, _ symbol: String,
                     _ key: ReferenceWritableKeyPath<Profile, Int>, defaultMinutes: Int) -> some View {
        let on = Binding<Bool>(
            get: { profile[keyPath: key] >= 0 },
            set: { enabled in
                profile[keyPath: key] = enabled ? defaultMinutes : -1
                Reminders.set(kind, minutes: profile[keyPath: key])
                if enabled { Task { _ = await Reminders.requestPermission() } }
            })
        let time = Binding<Date>(
            get: {
                let m = max(profile[keyPath: key], 0)
                return DateUtils.calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = DateUtils.calendar.dateComponents([.hour, .minute], from: date)
                profile[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                Reminders.set(kind, minutes: profile[keyPath: key])
            })
        return VStack(alignment: .leading) {
            Toggle(isOn: on) { Label(title, systemImage: symbol) }
            if on.wrappedValue {
                DatePicker("Hora", selection: time, displayedComponents: .hourAndMinute)
            }
        }
    }
}

/// Copia de seguridad: guardar todos tus datos en un archivo y recuperarlos.
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @State private var exporting = false
    @State private var importing = false
    @State private var document: BackupDocument?
    @State private var message: String?
    @State private var pending: AtlasBackup?

    var body: some View {
        Section {
            Button {
                if let data = try? AtlasBackup.encoder.encode(BackupService.make(context)) {
                    document = BackupDocument(data: data)
                    exporting = true
                }
            } label: { Label("Guardar copia de seguridad", systemImage: "square.and.arrow.up") }
            Button { importing = true } label: { Label("Recuperar una copia", systemImage: "square.and.arrow.down") }
            if let message { Text(message).font(.caption).foregroundStyle(DS.text2) }
        } header: { Text("Copia de seguridad") } footer: {
            Text("Guárdala en Archivos o iCloud Drive de vez en cuando. Las fotos de progreso no van en la copia.")
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "ATLAS-\(DateUtils.dayKey(Date()))") { result in
            if case .success = result { message = "Copia guardada." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let backup = try? AtlasBackup.decoder.decode(AtlasBackup.self, from: data) {
                pending = backup
            } else {
                message = "Ese archivo no es una copia de ATLAS."
            }
        }
        .confirmationDialog("¿Recuperar esta copia?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Recuperar (sustituye tus datos actuales)", role: .destructive) {
                if let b = pending {
                    BackupService.restore(b, into: context)
                    message = "Copia recuperada: \(b.foods.count) alimentos, \(b.workouts.count) entrenos y \(b.weights.count) pesajes."
                }
                pending = nil
            }
        }
    }
}
