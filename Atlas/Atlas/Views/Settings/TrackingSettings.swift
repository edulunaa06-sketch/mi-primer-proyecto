import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Objetivo de pasos

/// Objetivo de pasos: se ajusta solo cada día o lo pones tú a mano.
struct StepGoalSection: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            Toggle("Ajustar solo cada día", isOn: Binding(
                get: { settings.stepGoalAdaptive },
                set: { value in
                    settings.stepGoalAdaptive = value
                    settings.stepGoalAdjustedDayKey = ""
                    try? context.save()
                    if value { DataStore.updateAdaptiveStepGoal(context) }
                }
            ))
            .tint(Theme.accent)
            Stepper(value: Binding(get: { settings.stepGoal }, set: { setManually($0) }), in: 1000...40000, step: 500) {
                HStack {
                    Text("Objetivo")
                    Spacer()
                    Text("\(NumberFormat.integer(settings.stepGoal)) pasos").monospacedDigit().foregroundStyle(Theme.textSecondary)
                }
            }
            HStack {
                Text("Escribir número")
                Spacer()
                IntField(placeholder: "pasos", value: Binding(
                    get: { settings.stepGoal },
                    set: { if let v = $0, (500...50000).contains(v) { setManually(v) } }
                ), width: 110)
            }
        } header: {
            Text("Pasos")
        } footer: {
            Text(settings.stepGoalAdaptive
                 ? "AUTOMÁTICO: cada día se pone en la media de tus pasos de los 7 días anteriores + 5 % (redondeado a 250, entre 3.000 y 20.000). Necesita al menos 3 días con datos; si no, se queda como está. Si cambias el número a mano, deja de ajustarse solo."
                 : "MANUAL: el objetivo es el que pongas. Activa «Ajustar solo cada día» para que se adapte a tu media de la última semana.")
        }
    }

    private func setManually(_ value: Int) {
        guard value != settings.stepGoal else { return }
        settings.stepGoal = value
        settings.stepGoalAdaptive = false
        try? context.save()
    }
}

/// Hoja con el objetivo de pasos (se abre desde Inicio).
struct StepGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    var body: some View {
        NavigationStack {
            Form {
                if let settings = settingsList.first { StepGoalSection(settings: settings) }
            }
            .screenBackground()
            .navigationTitle("Objetivo de pasos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Avisos inteligentes

struct SmartRemindersSection: View {
    @Bindable var settings: UserSettings
    @Environment(\.modelContext) private var context
    @Environment(NotificationManager.self) private var notifications
    @Environment(StepCounter.self) private var steps
    @State private var problem: String?

    var body: some View {
        Section {
            Toggle("Aviso de pasos", isOn: toggle(\.stepReminderEnabled))
                .tint(Theme.accent)
            if settings.stepReminderEnabled {
                timeRow("Desde", \.stepReminderFromMinutes)
                timeRow("Hasta", \.stepReminderToMinutes)
            }
            Toggle("Recordar pesarme", isOn: toggle(\.weightReminderEnabled))
                .tint(Theme.accent)
            if settings.weightReminderEnabled {
                timeRow("Desde", \.weightReminderFromMinutes)
                timeRow("Hasta", \.weightReminderToMinutes)
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Avisos inteligentes")
        } footer: {
            Text("Pasos: solo avisa si vas por debajo de la mitad de tu objetivo. Peso: solo si ese día aún no te has pesado. Si «desde» y «hasta» son iguales avisa a esa hora; si no, a una hora dentro del rango. iOS no deja a la app mirar tus pasos a cualquier hora: se comprueba al abrir y cerrar la app y cuando iOS la deja actualizarse en segundo plano, así que el aviso de pasos dice cuántos llevabas en la última comprobación.")
        }
    }

    private func toggle(_ keyPath: ReferenceWritableKeyPath<UserSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in
            Task {
                if value, !(await notifications.ensurePermission()) {
                    problem = "Las notificaciones están desactivadas. Actívalas en Ajustes › Notificaciones › Now or Never."
                    settings[keyPath: keyPath] = false
                } else {
                    problem = nil
                    settings[keyPath: keyPath] = value
                }
                try? context.save()
                await refresh()
            }
        })
    }

    private func timeRow(_ title: String, _ keyPath: ReferenceWritableKeyPath<UserSettings, Int>) -> some View {
        DatePicker(title, selection: Binding(
            get: {
                let t = ClockTime(minutesOfDay: settings[keyPath: keyPath])
                return DateUtils.calendar.date(from: DateComponents(hour: t.hour, minute: t.minute)) ?? Date()
            },
            set: { date in
                let c = DateUtils.calendar.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = ClockTime(hour: c.hour ?? 0, minute: c.minute ?? 0).minutesOfDay
                try? context.save()
                Task { await refresh() }
            }
        ), displayedComponents: .hourAndMinute)
    }

    private func refresh() async {
        await ReminderCoordinator.refresh(context: context, notifications: notifications, todaySteps: steps.todaySteps)
    }
}

// MARK: - Copia de seguridad

struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @Environment(StravaService.self) private var strava
    @Environment(NotificationManager.self) private var notifications
    @Environment(StepCounter.self) private var steps

    @State private var exportDocument: BackupDocument?
    @State private var exportName = BackupFile.suggestedFileName(for: Date())
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pending: BackupFile?
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isWorking = false

    var body: some View {
        Section {
            Button {
                export()
            } label: {
                Label("Exportar copia de seguridad", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Importar copia de seguridad", systemImage: "square.and.arrow.down")
            }
            if isWorking { ProgressView() }
        } header: {
            Text("Copia de seguridad")
        } footer: {
            Text("Guarda en un archivo (por ejemplo, en iCloud Drive o en Archivos) todos tus datos: ajustes, pesos, entrenos, comidas, menús, carreras, pasos, días marcados y fotos. Importar una copia REEMPLAZA todos los datos actuales. No incluye la clave de Claude ni la conexión con Strava, que hay que volver a poner.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            switch result {
            case .success: show("Copia de seguridad guardada.")
            case .failure(let error): show("No se pudo guardar: \(error.localizedDescription)", error: true)
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): show("No se pudo abrir el archivo: \(error.localizedDescription)", error: true)
            }
        }
        .confirmationDialog("¿Reemplazar todos tus datos?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Reemplazar con la copia", role: .destructive) {
                if let file = pending { Task { await restore(file) } }
                pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            if let file = pending {
                Text("Copia del \(DateUtils.shortDate(file.createdAt)): \(file.summary). Lo que tienes ahora en la app se borrará.")
            }
        }
        .alert(messageIsError ? "No se pudo completar" : "Hecho",
               isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func export() {
        do {
            let file = try BackupService.makeBackup(context)
            exportDocument = BackupDocument(data: try file.encoded())
            exportName = BackupFile.suggestedFileName(for: file.createdAt)
            showExporter = true
        } catch {
            show("No se pudo crear la copia: \(error.localizedDescription)", error: true)
        }
    }

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pending = try BackupFile.decode(data)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func restore(_ file: BackupFile) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try BackupService.restore(file, into: context)
            // Los ejercicios tuyos de la copia vuelven al catálogo sin tener que reabrir la app.
            StrengthStore.refreshCustomCatalog(in: context)
            let s = DataStore.settings(context)
            strava.configure(clientID: s.stravaClientID)
            if s.creatineReminderEnabled { try? await notifications.scheduleCreatine(hour: s.creatineHour, minute: s.creatineMinute) }
            if s.photoReminderEnabled {
                let day = s.trackingStartDate.map { DateUtils.calendar.component(.day, from: $0) } ?? 22
                try? await notifications.schedulePhotoReminders(referenceDay: day, hour: s.photoReminderHour)
            }
            await ReminderCoordinator.refresh(context: context, notifications: notifications, todaySteps: steps.todaySteps)
            show("Copia importada: \(file.summary).")
        } catch {
            show("No se pudo importar: \(error.localizedDescription)", error: true)
        }
    }

    private func show(_ text: String, error: Bool = false) {
        messageIsError = error
        message = text
    }
}
