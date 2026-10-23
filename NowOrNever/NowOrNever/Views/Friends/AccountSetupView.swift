import SwiftUI

/// Se muestra una vez al entrar: nombre, @usuario y teléfono para que tus amigos te encuentren.
/// Sin correo ni contraseña. Si el servidor de amigos aún no está listo, se guarda y la cuenta se crea sola
/// en cuanto lo esté.
struct AccountSetupView: View {
    var onDone: () -> Void

    @Environment(SocialService.self) private var social
    @State private var name = ""
    @State private var username = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AMIGOS").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Theme.lime)
                        Text("Crea tu cuenta").font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        Text("Con tu nombre y tu teléfono, tus amigos y tu pareja te encuentran en la app y os podéis seguir. No hace falta correo ni contraseña.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Tu nombre (p. ej. Edu)", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(12).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onChange(of: name) { old, new in
                                if username.isEmpty || username == SocialAPI.suggestUsername(old) { username = SocialAPI.suggestUsername(new) }
                            }
                            .accessibilityIdentifier("account.name")
                        HStack(spacing: 4) {
                            Text("@").foregroundStyle(Theme.textSecondary)
                            TextField("usuario", text: $username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .padding(12).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        TextField("Tu teléfono (600 11 22 33)", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .padding(12).background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("En el servidor no se guarda tu número, solo un código sacado de él. Quien te tenga en su agenda podrá encontrarte; para seguirte siempre tendrás que aceptar.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .card()
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView().tint(.black) } else { Text("Crear mi cuenta") }
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(username.count < 3 || saving)
                    Button("Ahora no") {
                        UserDefaults.standard.set(true, forKey: SocialService.accountPromptKey)
                        onDone()
                    }
                    .buttonStyle(LimeButtonStyle(filled: false))
                    Text("Puedes hacerlo más tarde en la pestaña Amigos.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try social.savePendingStart(name: name, username: username, phone: phone)
            try await social.completePendingStart()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
