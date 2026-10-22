import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]

    var body: some View {
        NavigationStack {
            Group {
                if let settings = settingsList.first {
                    SettingsForm(settings: settings)
                } else {
                    ProgressView()
                }
            }
            .screenBackground()
            .navigationTitle("Ajustes")
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: UserSettings

    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(NotificationManager.self) private var notifications
    @Environment(StravaService.self) private var strava
    @Environment(HealthKitManager.self) private var health

    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var steps: Double?
    @State private var creatineTime = Date()
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var showOnboarding = false
    @State private var stravaClientID = ""
    @State private var stravaBackend = ""
    @State private var showProfile = false
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    var body: some View {
        Form {
            profileSection
            goalsSection
            creatineSection
            photoSection
            notificationsStatusSection
            healthSection
            stravaSection
            trackingSection
            dataSection
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
        .navigationDestination(isPresented: $showProfile) { ProfileView(settings: settings) }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-NNProfile") { showProfile = true }
        }
        #endif
        .task { await notifications.refreshStatus() }
        .onChange(of: settings.trackingStartDate) { _, _ in
            // Si cambia la fecha de referencia, se reprograma el recordatorio de fotos.
            if settings.photoReminderEnabled { Task { await setPhotoReminder(enabled: true) } }
        }
        .alert(feedbackIsError ? "No se pudo completar" : "Hecho",
               isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("OK", role: .cancel) {}
            if feedbackIsError {
                Button("Abrir Ajustes de iOS") { openSystemSettings() }
            }
        } message: { Text(feedback ?? "") }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
        }
    }

    // MARK: Perfil

    private var profileSection: some View {
        Section {
            Button { showProfile = true } label: {
                HStack {
                    Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(Theme.lime)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Perfil personal").foregroundStyle(Theme.textPrimary)
                        Text(profileSummary).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        } footer: {
            Text(settings.autoTargets
                 ? "Objetivos AUTOMÁTICOS: calculados con Mifflin-St Jeor según tu perfil."
                 : "Objetivos MANUALES. Completa tu perfil para calcularlos automáticamente.")
        }
    }

    private var profileSummary: String {
        var parts: [String] = []
        if let w = weights.first?.weightKg { parts.append("\(NumberFormat.kg(w)) kg") }
        if let h = settings.heightCm { parts.append("\(NumberFormat.integer(h)) cm") }
        if let a = settings.age { parts.append("\(a) años") }
        if settings.heightCm != nil { parts.append(settings.goal.label) }
        return parts.isEmpty ? "Peso, altura, edad, sexo, actividad y objetivo" : parts.joined(separator: " · ")
    }

    // MARK: Objetivos

    private var goalsSection: some View {
        Section {
            numberRow("Calorías (kcal)", $kcal)
            numberRow("Proteínas (g)", $protein)
            numberRow("Carbohidratos (g)", $carbs)
            numberRow("Grasas (g)", $fat)
            numberRow("Pasos diarios", $steps)
            Button("Guardar objetivos") { saveGoals() }
                .disabled([kcal, protein, carbs, fat, steps].contains { ($0 ?? 0) <= 0 })
        } header: {
            Text("Objetivos diarios")
        } footer: {
            Text(settings.autoTargets
                 ? "Calculados automáticamente desde tu perfil. Si los cambias y guardas aquí pasarán a ser manuales. No son una recomendación clínica."
                 : "Valores manuales (iniciales provisionales: 2.300 kcal, 180 g P, 250 g C, 65 g G, 8.000 pasos). No son una recomendación clínica.")
        }
    }

    // MARK: Creatina

    private var creatineSection: some View {
        Section {
            Toggle("Recordatorio diario", isOn: Binding(
                get: { settings.creatineReminderEnabled },
                set: { newValue in Task { await setCreatine(enabled: newValue) } }
            ))
            DatePicker("Hora", selection: $creatineTime, displayedComponents: .hourAndMinute)
                .onChange(of: creatineTime) { _, _ in
                    guard settings.creatineReminderEnabled else { return }
                    Task { await setCreatine(enabled: true) }
                }
            Button("Enviar notificación de prueba (5 s)") {
                Task {
                    do {
                        try await notifications.scheduleTest()
                        show("Notificación de prueba programada. Debería aparecer en unos 5 segundos (sal de la app para verla como banner).")
                    } catch {
                        show(error.localizedDescription, error: true)
                    }
                }
            }
        } header: {
            Text("Creatina")
        } footer: {
            Text(settings.creatineReminderEnabled
                 ? "Programado cada día a las \(String(format: "%02d:%02d", settings.creatineHour, settings.creatineMinute)). Cambiar la hora sustituye el recordatorio, no lo duplica."
                 : "Desactivado.")
        }
    }

    private func setCreatine(enabled: Bool) async {
        let comps = DateUtils.calendar.dateComponents([.hour, .minute], from: creatineTime)
        let hour = comps.hour ?? 9, minute = comps.minute ?? 0
        if enabled {
            do {
                try await notifications.scheduleCreatine(hour: hour, minute: minute)
                settings.creatineReminderEnabled = true
                settings.creatineHour = hour
                settings.creatineMinute = minute
                try? context.save()
            } catch {
                settings.creatineReminderEnabled = false
                try? context.save()
                show(error.localizedDescription, error: true)
            }
        } else {
            await notifications.cancelCreatine()
            settings.creatineReminderEnabled = false
            try? context.save()
        }
    }

    // MARK: Fotos

    /// Día del recordatorio de fotos: el de la fecha de inicio del seguimiento o, si no hay, el 22.
    private var referenceDay: Int? {
        settings.trackingStartDate.map { DateUtils.calendar.component(.day, from: $0) } ?? 22
    }

    private var photoSection: some View {
        Section {
            Toggle("Recordatorio mensual", isOn: Binding(
                get: { settings.photoReminderEnabled },
                set: { newValue in Task { await setPhotoReminder(enabled: newValue) } }
            ))
            Stepper("Hora: \(settings.photoReminderHour):00", value: Binding(
                get: { settings.photoReminderHour },
                set: { newValue in
                    settings.photoReminderHour = newValue
                    try? context.save()
                    if settings.photoReminderEnabled { Task { await setPhotoReminder(enabled: true) } }
                }
            ), in: 6...23)
        } header: {
            Text("Fotos de progreso")
        } footer: {
            if let day = referenceDay {
                Text(day <= 28
                     ? "El día \(day) de cada mes a las \(settings.photoReminderHour):00 (día de tu fecha de inicio, o el 22 si no la has configurado). Pide las tres vistas: frente, lateral y espalda."
                     : "Tu día de referencia es el \(day): en los meses que no lo tienen se usará el último día del mes. Se programan 12 meses y se renuevan al abrir la app.")
            } else {
                Text("Configura la fecha de inicio del seguimiento (más abajo) para activar el recordatorio.")
            }
        }
    }

    private func setPhotoReminder(enabled: Bool) async {
        guard let day = referenceDay else { return }
        if enabled {
            do {
                try await notifications.schedulePhotoReminders(referenceDay: day, hour: settings.photoReminderHour)
                settings.photoReminderEnabled = true
            } catch {
                settings.photoReminderEnabled = false
                show(error.localizedDescription, error: true)
            }
        } else {
            await notifications.cancelPhotoReminders()
            settings.photoReminderEnabled = false
        }
        try? context.save()
    }

    private var notificationsStatusSection: some View {
        Section("Estado de notificaciones") {
            LabeledContent("Permiso", value: authorizationText)
            LabeledContent("Programadas", value: "\(notifications.pendingIDs.count)")
            if notifications.authorization == .denied {
                Button("Abrir Ajustes de iOS") { openSystemSettings() }
            } else if notifications.authorization == .notDetermined {
                Button("Solicitar permiso") { Task { _ = await notifications.requestAuthorization() } }
            }
        }
    }

    private var authorizationText: String {
        switch notifications.authorization {
        case .authorized: return "Concedido"
        case .denied: return "Denegado"
        case .notDetermined: return "Sin solicitar"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporal"
        @unknown default: return "Desconocido"
        }
    }

    // MARK: Salud

    private var healthSection: some View {
        Section {
            switch health.state {
            case .unavailable:
                Text("Salud no disponible en este dispositivo.")
            case .notDetermined:
                Button("Permitir lectura de pasos") { Task { await health.requestAuthorization() } }
            case .requested, .error:
                Text("Solicitud de permiso ya mostrada. Para cambiarlo: Ajustes › Salud › Acceso a datos y dispositivos › Now or Never.")
                    .font(.footnote)
                Button("Abrir Ajustes de iOS") { openSystemSettings() }
            }
        } header: {
            Text("Apple Salud")
        }
    }

    // MARK: Strava

    private var stravaSection: some View {
        Section {
            switch strava.status {
            case .notConfigured:
                Label("Pendiente de configuración", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
            case .disconnected:
                Label("Configurado · no conectado", systemImage: "link")
            case .connected(let expires):
                Label("Conectado", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                Text("Token válido hasta \(expires.formatted(date: .abbreviated, time: .shortened)) (se renueva solo)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            TextField("Client ID de tu app de Strava", text: $stravaClientID)
                .keyboardType(.numberPad)
            TextField("URL del backend (https://…)", text: $stravaBackend)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Guardar configuración") {
                settings.stravaClientID = stravaClientID.trimmingCharacters(in: .whitespaces)
                settings.stravaBackendURL = stravaBackend.trimmingCharacters(in: .whitespaces)
                try? context.save()
                strava.configure(clientID: settings.stravaClientID, backendURL: settings.stravaBackendURL)
                if !strava.isConfigured {
                    show("Configuración incompleta: el Client ID debe ser numérico y el backend una URL https válida.", error: true)
                }
            }
            switch strava.status {
            case .disconnected:
                Button("Conectar con Strava") { Task { await connectStrava() } }
            case .connected:
                Button("Importar carreras ahora") {
                    Task {
                        let count = await strava.syncRuns(into: context)
                        if let error = strava.lastError { show(error, error: true) }
                        else { show("Importación completada: \(count) carreras recibidas de Strava.") }
                    }
                }
                Button("Desconectar Strava", role: .destructive) { Task { await strava.disconnect() } }
            case .notConfigured:
                EmptyView()
            }
            if strava.isWorking { ProgressView() }
            if let error = strava.lastError {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Strava")
        } footer: {
            Text("El botón “Abrir Strava” funciona siempre. Importar carreras requiere crear una app en strava.com/settings/api y un backend propio que guarde el client_secret (ver README). El secreto nunca se guarda en la app; los tokens se guardan en el Llavero.")
        }
    }

    private func connectStrava() async {
        guard let url = strava.makeAuthorizationURL() else {
            show("Configura primero el Client ID y el backend.", error: true)
            return
        }
        do {
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: StravaAPI.callbackScheme)
            await strava.handleCallback(callback)
            if let error = strava.lastError {
                show(error, error: true)
            } else if case .connected = strava.status {
                show("Cuenta de Strava conectada.")
            }
        } catch {
            show("Conexión cancelada o fallida: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Seguimiento

    private var trackingSection: some View {
        Section {
            if let start = settings.trackingStartDate {
                LabeledContent("Inicio del seguimiento", value: DateUtils.shortDate(start))
            } else {
                Text("Sin fecha de inicio configurada.")
            }
            Button("Configurar peso y fecha de inicio") { showOnboarding = true }
        } header: {
            Text("Seguimiento")
        }
    }

    private var dataSection: some View {
        Section {
            Text("Todos los datos (pesos, entrenamientos, comidas, ajustes y fotos) se guardan solo en este iPhone. No hay cuentas ni servidores propios.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
        } header: {
            Text("Privacidad y datos")
        }
    }

    // MARK: Utilidades

    private func numberRow(_ title: String, _ binding: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(placeholder: "0", value: binding, width: 100)
        }
    }

    private func load() {
        kcal = settings.kcalTarget
        protein = settings.proteinTarget
        carbs = settings.carbsTarget
        fat = settings.fatTarget
        steps = Double(settings.stepGoal)
        var comps = DateComponents()
        comps.hour = settings.creatineHour
        comps.minute = settings.creatineMinute
        creatineTime = DateUtils.calendar.date(from: comps) ?? Date()
        stravaClientID = settings.stravaClientID
        stravaBackend = settings.stravaBackendURL
    }

    private func saveGoals() {
        guard let kcal, let protein, let carbs, let fat, let steps else { return }
        settings.stepGoal = Int(steps.rounded())
        let targetsChanged = [kcal, protein, carbs, fat] != [settings.kcalTarget, settings.proteinTarget, settings.carbsTarget, settings.fatTarget]
        settings.kcalTarget = kcal
        settings.proteinTarget = protein
        settings.carbsTarget = carbs
        settings.fatTarget = fat
        // Editar los objetivos a mano desactiva el cálculo automático para no sobrescribirlos.
        if targetsChanged { settings.autoTargets = false }
        try? context.save()
        let macroKcal = protein * 4 + carbs * 4 + fat * 9
        if abs(macroKcal - kcal) / kcal > 0.1 {
            show("Objetivos guardados. Aviso: tus macros suman ≈ \(NumberFormat.integer(macroKcal)) kcal, distinto de las \(NumberFormat.integer(kcal)) kcal objetivo.")
        } else {
            show("Objetivos guardados.")
        }
    }

    private func show(_ message: String, error: Bool = false) {
        feedbackIsError = error
        feedback = message
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
