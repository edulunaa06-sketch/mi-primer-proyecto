import SwiftData
import SwiftUI

/// Amigos: cuenta propia, seguir a otras personas con la app (con solicitud que la otra persona acepta)
/// y ver sus días: qué entrenó, qué no, qué comió y sus pasos.
struct FriendsView: View {
    @Environment(SocialService.self) private var social
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context

    @AppStorage(SocialService.shareKey) private var share = true
    @State private var message: String?
    @State private var isError = false
    @State private var searchName = ""
    @State private var results: [SocialAPI.Profile] = []
    @State private var searching = false
    @State private var contacts: [SocialAPI.Profile]?
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !social.isConfigured {
                        ServerSetupCard()
                    } else if !social.isSignedIn || social.me == nil {
                        StartCard()
                    } else {
                        meCard
                        addFriendCard
                        if !social.incoming.isEmpty { requestsCard }
                        followingCard
                        followersCard
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(isError ? Theme.danger : Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    privacyNote
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Amigos")
            .refreshable { await sync() }
            .task { await sync() }
        }
    }

    private var meCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NavigationLink {
                    MyProfileView()
                } label: {
                    HStack {
                        Avatar(profile: social.me, size: 52)
                        VStack(alignment: .leading) {
                            Text(social.me?.shownName ?? "").font(.headline)
                            Text("@\(social.me?.username ?? "") · Ver mi perfil").font(.subheadline).foregroundStyle(Theme.textSecondary)
                                .accessibilityIdentifier("friends.me")
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                // Una cuenta creada solo con nombre no tiene correo: si cierras sesión no se puede recuperar.
                if social.session?.email != nil {
                    Menu {
                        Button("Cerrar sesión", role: .destructive) { social.signOut() }
                    } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                }
            }
            Toggle("Compartir mis entrenos, comidas y pasos", isOn: $share).tint(Theme.lime)
            Text(share
                 ? (social.lastPublished.map { "Compartido a las \($0.formatted(date: .omitted, time: .shortened)). Solo lo ven las personas que aceptas." }
                    ?? "Se comparte al abrir la app y al entrar aquí. Solo lo ven las personas que aceptas.")
                 : "No se comparte nada nuevo. Lo ya compartido sigue visible para tus seguidores.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private var addFriendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Buscar amigos", subtitle: "Escribe su nombre o su @usuario. Te tiene que aceptar.")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Nombre o @usuario", text: $searchName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("friends.search")
                if searching { ProgressView() }
            }
            .padding(10)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            ForEach(results) { person in
                HStack {
                    Avatar(profile: person, size: 40)
                    VStack(alignment: .leading) {
                        Text(person.shownName).font(.subheadline.weight(.semibold))
                        Text("@\(person.username)").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    followButton(person)
                }
            }
            if !searching && results.isEmpty && searchName.trimmingCharacters(in: .whitespaces).count >= 2 {
                Text("No hay nadie con ese nombre todavía.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Button {
                Task {
                    do { contacts = try await social.contactsOnApp() } catch { message = error.localizedDescription; isError = true }
                }
            } label: {
                Label("Buscar en mis contactos", systemImage: "person.crop.circle.badge.checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle(filled: false))
            .disabled(social.isWorking)
            if let contacts {
                if contacts.isEmpty {
                    Text("Ninguno de tus contactos usa la app todavía (o no ha puesto su teléfono).")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                ForEach(contacts) { person in
                    HStack {
                        Avatar(profile: person, size: 40)
                        VStack(alignment: .leading) {
                            Text(person.shownName).font(.subheadline.weight(.semibold))
                            Text("@\(person.username) · en tus contactos").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        followButton(person)
                    }
                }
            }
            if social.savedPhone == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pon tu teléfono para que tus contactos te encuentren").font(.caption.weight(.semibold))
                    HStack {
                        TextField("600 11 22 33", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .padding(10)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button("Guardar") {
                            Task { await run("Teléfono guardado. Tus contactos ya pueden encontrarte.") { try await social.setPhone(phone) } }
                        }
                        .buttonStyle(LimeButtonStyle())
                        .fixedSize()
                        .disabled(phone.filter(\.isNumber).count < 8 || social.isWorking)
                    }
                    Text("En el servidor solo se guarda un código sacado del número, no el número.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            if !social.outgoing.isEmpty {
                Text("Pendientes de aceptar: " + social.outgoing.map { "@\($0.username)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .task(id: searchName) {
            let text = searchName
            guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                results = try await social.search(text)
            } catch {
                message = error.localizedDescription
                isError = true
            }
        }
    }

    @ViewBuilder
    private func followButton(_ person: SocialAPI.Profile) -> some View {
        if social.following.contains(where: { $0.id == person.id }) {
            Text("Siguiendo").font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
        } else if social.outgoing.contains(where: { $0.id == person.id }) {
            Text("Pendiente").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        } else {
            Button("Seguir") {
                Task { await run("Solicitud enviada a @\(person.username)") { try await social.follow(person) } }
            }
            .buttonStyle(LimeButtonStyle())
            .fixedSize()
            .disabled(social.isWorking)
        }
    }

    private var requestsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Solicitudes", subtitle: "Quieren ver tus entrenos y comidas")
            ForEach(social.incoming) { person in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(person.shownName) · @\(person.username)").font(.subheadline.weight(.semibold))
                    HStack {
                        Button("Aceptar y seguir") { Task { await run("Ahora os seguís") { try await social.accept(person, followBack: true) } } }
                            .buttonStyle(LimeButtonStyle())
                        Button("Solo aceptar") { Task { await run("Aceptada") { try await social.accept(person, followBack: false) } } }
                            .buttonStyle(LimeButtonStyle(filled: false))
                        Button(role: .destructive) { Task { await run("Rechazada") { try await social.removeFollower(person) } } } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .card()
    }

    private var followingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sigues a", subtitle: social.following.isEmpty ? "Aún no sigues a nadie" : "Toca para ver sus días")
            ForEach(social.following) { person in
                NavigationLink {
                    FriendDetailView(person: person)
                } label: {
                    HStack {
                        Avatar(profile: person, size: 40)
                        VStack(alignment: .leading) {
                            Text(person.shownName).font(.subheadline.weight(.semibold))
                            Text("@\(person.username)").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Dejar de seguir", role: .destructive) { Task { await run("Ya no sigues a @\(person.username)") { try await social.unfollow(person) } } }
                }
            }
        }
        .card()
    }

    private var followersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Te siguen", subtitle: social.followers.isEmpty ? "Nadie todavía" : "Ven tus entrenos, comidas y pasos")
            ForEach(social.followers) { person in
                HStack {
                    Text("\(person.shownName) · @\(person.username)").font(.subheadline)
                    Spacer()
                    Button("Quitar", role: .destructive) { Task { await run("@\(person.username) ya no te sigue") { try await social.removeFollower(person) } } }
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .card()
    }

    private var privacyNote: some View {
        Text("Se comparte un resumen por día: sesiones programadas (hechas o no) y mejores series, comidas y kcal, y pasos. Nunca fotos, peso corporal ni datos de Salud aparte de los pasos. Tus datos completos siguen solo en tu iPhone.")
            .font(.caption2).foregroundStyle(Theme.textTertiary)
    }

    private func sync() async {
        guard social.isSignedIn else { return }
        do {
            try await social.refreshFriends()
            try await SocialSync.publish(social: social, health: health, context: context)
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func run(_ success: String, _ action: () async throws -> Void) async {
        do {
            try await action()
            message = success
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}

/// Sube los resúmenes de los últimos 7 días.
enum SocialSync {
    @MainActor
    static func publish(social: SocialService, health: HealthKitManager, context: ModelContext) async throws {
        guard social.isSignedIn, social.me != nil else { return }
        let steps = Dictionary(health.history.map { (DateUtils.startOfDay($0.date), $0.steps) }, uniquingKeysWith: { a, _ in a })
        let summaries = DataStore.socialSummaries(steps: steps, todaySteps: health.todaySteps, in: context)
        try await social.publish(summaries)
        let settings = DataStore.settings(context)
        let photos = (try? context.fetch(FetchDescriptor<ProgressPhoto>())) ?? []
        let local = photos.map { photo in
            SocialService.LocalPhoto(month: String(format: "%04d-%02d", photo.year, photo.month), view: photo.viewRaw,
                                     takenOn: SocialAPI.dayString(photo.updatedAt, calendar: DateUtils.calendar),
                                     version: String(Int(photo.updatedAt.timeIntervalSince1970)),
                                     jpeg: { [fileName = photo.fileName] in PhotoStorage.loadImage(fileName).flatMap { ProfileImage.jpeg($0, maxSide: 1280) } })
        }
        try await social.syncProfile(heightCm: settings.heightCm, weightKg: DataStore.latestWeight(context), photos: local)
    }
}

// MARK: - Configuración y cuenta

private struct ServerSetupCard: View {
    @Environment(SocialService.self) private var social
    @State private var url = ""
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Conectar el servidor de amigos",
                          subtitle: "Una sola vez. Es gratis: crea un proyecto en supabase.com siguiendo la guía AMIGOS.md y pega aquí su URL y su clave pública. Tu pareja debe poner los mismos datos.")
            TextField("https://xxxx.supabase.co", text: $url)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            TextField("Clave pública (anon / publishable)", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Guardar") {
                do { try social.configure(url: url, apiKey: key); error = nil } catch { self.error = error.localizedDescription }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(url.isEmpty || key.isEmpty)
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            Text("Nunca pegues la clave «secret» ni «service_role»: solo la pública.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
        .onAppear { url = social.savedURL; key = social.savedAPIKey }
    }
}

private struct AccountCard: View {
    @Environment(SocialService.self) private var social
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Correo", text: $email)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            SecureField("Contraseña", text: $password)
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Entrar") {
                Task {
                    do { try await social.signIn(email: email, password: password) } catch { message = error.localizedDescription }
                }
            }
            .buttonStyle(LimeButtonStyle(filled: false))
            .disabled(email.isEmpty || password.isEmpty || social.isWorking)
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.danger) }
        }
    }
}

/// Empezar: solo tu @usuario y tu nombre. Sin correo ni contraseña.
private struct StartCard: View {
    @Environment(SocialService.self) private var social
    @State private var username = ""
    @State private var name = ""
    @State private var error: String?
    @State private var withEmail = false
    @State private var phone = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Elige tu nombre", subtitle: "Con esto tus amigos te encuentran en la app. No hace falta correo ni contraseña.")
            TextField("Tu nombre (p. ej. Edu)", text: $name)
                .textInputAutocapitalization(.words)
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: name) { old, new in
                    // Sugerencia de @usuario a partir del nombre mientras no lo hayas tocado.
                    if username.isEmpty || username == Self.suggest(old) { username = Self.suggest(new) }
                }
            HStack(spacing: 4) {
                Text("@").foregroundStyle(Theme.textSecondary)
                TextField("usuario", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("friends.username")
            }
            .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            TextField("Tu teléfono (opcional: así te encuentran tus contactos)", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .padding(10).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                Task {
                    do {
                        if !phone.isEmpty && SocialAPI.normalizePhone(phone) == nil { throw SocialAPI.SocialError.invalidPhone }
                        try await social.start(username: username, displayName: name)
                        if !phone.isEmpty { try await social.setPhone(phone) }
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            } label: {
                if social.isWorking { ProgressView().tint(.black) } else { Text("Empezar") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(username.count < 3 || social.isWorking)
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            Text("Tu cuenta queda guardada en este iPhone. Tus entrenos y comidas siguen solo en tu móvil.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
            Button(withEmail ? "Ocultar" : "Ya tengo cuenta con correo") { withEmail.toggle() }
                .font(.footnote)
            if withEmail { AccountCard() }
        }
        .card()
    }

    /// «Edu Luna» → «eduluna».
    static func suggest(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.").contains($0) }.prefix(20))
    }
}

// MARK: - Días de un amigo

struct FriendDetailView: View {
    let person: SocialAPI.Profile
    @Environment(SocialService.self) private var social
    @State private var days: [SocialAPI.DaySummary] = []
    @State private var detail = SocialService.ProfileDetail()
    @State private var tab = 0
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    Avatar(profile: person, size: 88)
                    Text(person.shownName).font(.title2.weight(.heavy))
                    Text("@\(person.username)").foregroundStyle(Theme.textSecondary)
                    FollowCountsRow(followers: detail.counts?.followers ?? 0, following: detail.counts?.following ?? 0)
                    if detail.stats?.heightCm != nil || detail.stats?.weightKg != nil {
                        StatsRow(heightCm: detail.stats?.heightCm, weightKg: detail.stats?.weightKg)
                    }
                }
                .frame(maxWidth: .infinity)
                .card()
                Picker("", selection: $tab) {
                    Text("Entrenos y comidas").tag(0)
                    Text("Fotos").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 1 {
                    FriendPhotosView(rows: detail.photos)
                } else {
                    daysContent
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(person.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private var daysContent: some View {
        VStack(spacing: 14) {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger).card()
                } else if loaded && days.isEmpty {
                    EmptyStateView(symbol: "calendar", title: "Sin días compartidos",
                                   message: "Aparecerán cuando \(person.shownName) abra la app con «Compartir» activado.")
                        .card()
                }
                if !days.isEmpty { weekCard }
                ForEach(days, id: \.day) { day in dayCard(day) }
        }
    }

    private var weekCard: some View {
        let week = days.prefix(7)
        let planned = week.reduce(0) { $0 + $1.trainingPlanned }
        let done = week.reduce(0) { $0 + $1.trainingDone }
        let missed = week.filter { $0.trainingDone < $0.trainingPlanned && !isToday($0.day) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Últimos 7 días").font(.headline)
            Text("Entrenos: \(done) de \(planned)").font(.title3.weight(.bold)).foregroundStyle(Theme.lime)
            if missed.isEmpty {
                Text("No se ha saltado ningún entreno.").font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Sin entrenar: " + missed.map { dayLabel($0.day) }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(Theme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func dayCard(_ day: SocialAPI.DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayLabel(day.day)).font(.headline)
                Spacer()
                if let steps = day.steps {
                    Label(NumberFormat.integer(steps), systemImage: "figure.walk").font(.caption.weight(.semibold))
                        .foregroundStyle(steps >= day.stepGoal ? Theme.lime : Theme.textSecondary)
                }
            }
            if day.sessions.isEmpty {
                Label("Descanso", systemImage: "bed.double.fill").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            ForEach(day.sessions, id: \.title) { session in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: session.completed ? "checkmark.circle.fill" : (isToday(day.day) ? "circle" : "xmark.circle.fill"))
                            .foregroundStyle(session.completed ? Theme.lime : (isToday(day.day) ? Theme.textTertiary : Theme.danger))
                        Text(session.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        if session.kind == "strength" {
                            Text("\(session.exercisesDone)/\(session.exercisesTotal) ejercicios").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    ForEach(session.highlights, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(Theme.textSecondary).padding(.leading, 26)
                    }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            ForEach(day.meals, id: \.type) { meal in
                HStack(alignment: .top) {
                    Image(systemName: meal.eaten ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(meal.eaten ? Theme.lime : Theme.textTertiary).font(.caption)
                    Text("\(meal.type): ").font(.caption.weight(.semibold)) + Text(meal.name).font(.caption)
                    Spacer()
                    Text("\(NumberFormat.integer(meal.kcal)) kcal").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Comido: \(NumberFormat.integer(day.kcalEaten)) de \(NumberFormat.integer(day.kcalTarget)) kcal · P \(NumberFormat.integer(day.proteinEaten)) g")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
        }
        .card()
    }

    private func load() async {
        do {
            days = try await social.summaries(of: person)
            detail = try await social.profileDetail(of: person.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func isToday(_ day: String) -> Bool { day == SocialAPI.dayString(Date(), calendar: DateUtils.calendar) }

    private func dayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = DateUtils.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return day }
        if isToday(day) { return "Hoy" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "es_ES"))).capitalized
    }
}
