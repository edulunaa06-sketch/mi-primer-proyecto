import SwiftData
import SwiftUI

/// Perfil y ajustes: datos personales, objetivos (automáticos o tuyos), metas diarias y datos.
struct ProfileSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var weight: Double?
    @State private var confirmErase = false

    var body: some View {
        NavigationStack {
            if let p = profiles.first {
                ProfileForm(profile: p, weight: $weight, confirmErase: $confirmErase)
                    .navigationTitle("Perfil")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") {
                                if let weight, weight != Store.latestWeight(context)?.kg { Store.logWeight(weight, in: context) }
                                p.recalculate(weightKg: weight ?? Store.latestWeight(context)?.kg)
                                try? context.save()
                                dismiss()
                            }
                        }
                        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { hideKeyboard() } }
                    }
                    .confirmationDialog("¿Borrar todos tus datos?", isPresented: $confirmErase, titleVisibility: .visible) {
                        Button("Borrar todo", role: .destructive) {
                            Store.eraseAll(context)
                            Store.seedTemplatesIfNeeded(context)
                            _ = Store.profile(context)
                            dismiss()
                        }
                    } message: { Text("Comidas, entrenos, pesos y rutinas. No se puede deshacer.") }
            }
        }
        .onAppear { weight = Store.latestWeight(context)?.kg }
        .presentationBackground(DS.bg)
    }
}

struct ProfileForm: View {
    @Bindable var profile: Profile
    @Binding var weight: Double?
    @Binding var confirmErase: Bool

    var body: some View {
        Form {
            Section("Tú") {
                TextField("Nombre", text: $profile.name)
                Picker("Sexo", selection: $profile.sexRaw) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("Edad: \(profile.age) años", value: $profile.age, in: 14...90)
                Stepper("Altura: \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 130...220, step: 1)
                HStack {
                    Text("Peso")
                    Spacer()
                    NumberField(placeholder: "kg", value: $weight, width: 100)
                    Text("kg").foregroundStyle(DS.text3)
                }
            }
            Section {
                Picker("Objetivo", selection: $profile.goalRaw) {
                    ForEach(FitnessGoal.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Actividad", selection: $profile.activityRaw) {
                    ForEach(ActivityLevel.allCases) { Text("\($0.label) · \($0.detail)").tag($0.rawValue) }
                }
            } header: { Text("Objetivo") } footer: {
                Text("Las calorías salen de la fórmula de Mifflin-St Jeor y tu actividad. Con 2 semanas de datos, en Progreso verás tu gasto REAL.")
            }
            Section {
                Toggle("Escribirlos yo", isOn: $profile.manualTargets)
                if profile.manualTargets {
                    targetRow("Calorías", $profile.kcalTarget, "kcal")
                    targetRow("Proteína", $profile.proteinTarget, "g")
                    targetRow("Hidratos", $profile.carbsTarget, "g")
                    targetRow("Grasa", $profile.fatTarget, "g")
                } else {
                    LabeledContent("Calorías", value: "\(NumberFormat.integer(profile.kcalTarget)) kcal")
                    LabeledContent("Proteína · Hidratos · Grasa",
                                   value: "\(Int(profile.proteinTarget)) · \(Int(profile.carbsTarget)) · \(Int(profile.fatTarget)) g")
                }
                Picker("Margen del objetivo", selection: $profile.kcalMargin) {
                    ForEach([50.0, 100, 150, 200], id: \.self) { Text("± \(Int($0)) kcal").tag($0) }
                }
            } header: { Text("Calorías y macros") } footer: {
                Text("Dentro del margen, el día cuenta como objetivo cumplido.")
            }
            Section("Metas diarias") {
                Stepper("Pasos: \(NumberFormat.integer(profile.stepGoal))", value: $profile.stepGoal, in: 2000...30000, step: 500)
                Stepper("Agua: \(String(format: "%.2f", Double(profile.waterGoalMl) / 1000).replacingOccurrences(of: ".", with: ",")) L",
                        value: $profile.waterGoalMl, in: 1000...6000, step: 250)
            }
            Section {
                Button("Borrar todos mis datos", role: .destructive) { confirmErase = true }
            } footer: {
                Text("ATLAS guarda todo solo en este iPhone. Valores nutricionales y cálculos orientativos: no sustituyen a un profesional.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AtlasBackground())
    }

    private func targetRow(_ title: String, _ value: Binding<Double>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            NumberField(placeholder: "0", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0 ?? 0 }), decimals: false, width: 100)
            Text(unit).foregroundStyle(DS.text3).frame(width: 34, alignment: .leading)
        }
    }
}

/// Bienvenida: en 4 pasos calcula tu plan de calorías y macros y deja lista tu rutina.
struct OnboardingView: View {
    let onFinish: () -> Void
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var name = ""
    @State private var sex: BiologicalSex = .male
    @State private var age: Double? = 28
    @State private var height: Double? = 175
    @State private var weight: Double? = 78
    @State private var goal: FitnessGoal = .recomposition
    @State private var activity: ActivityLevel = .moderate
    @State private var shownKcal: Double = 0

    private var body_: BodyProfile? {
        guard let a = age, let h = height, let w = weight else { return nil }
        let p = BodyProfile(weightKg: w, heightCm: h, age: Int(a), sex: sex, activity: activity, goal: goal)
        return p.isValid ? p : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= page ? AnyShapeStyle(DS.brand) : AnyShapeStyle(DS.surfaceHi)).frame(height: 4)
                }
            }
            .padding(.horizontal, 24).padding(.top, 12)
            TabView(selection: $page) {
                welcome.tag(0)
                about.tag(1)
                goalPage.tag(2)
                plan.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)
            Button {
                hideKeyboard()
                if page < 3 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page == 0 ? "Empezar" : page == 3 ? "Vamos allá" : "Siguiente")
            }
            .buttonStyle(.primary)
            .disabled(page == 1 && body_ == nil)
            .padding(24)
            .accessibilityIdentifier("onboarding.next")
        }
        .background(AtlasBackground())
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            AtlasLogo(size: 130)
                .shadow(color: DS.indigo.opacity(0.6), radius: 30)
            Text("ATLAS").font(.display(40, .black)).tracking(8)
            VStack(alignment: .leading, spacing: 14) {
                bullet("flame.fill", "Calorías y macros", "Apunta en segundos y elige platos ajustados a lo que te queda.")
                bullet("dumbbell.fill", "Entrenos con coach", "Te dice qué peso tocar, cronometra el descanso y celebra cada récord.")
                bullet("chart.xyaxis.line", "Progreso de verdad", "Peso de tendencia, tu gasto real y tu fuerza en cada ejercicio.")
            }
            .padding(.horizontal, 28)
            Spacer()
        }
    }

    private func bullet(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(DS.brandDiagonal).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(text).font(.system(size: 13)).foregroundStyle(DS.text2)
            }
        }
    }

    private var about: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sobre ti").font(.display(28))
                Text("Para calcular tus calorías. Se queda en tu iPhone.").font(.footnote).foregroundStyle(DS.text2)
                TextField("Tu nombre", text: $name)
                    .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.surfaceHi))
                    .accessibilityIdentifier("onboarding.name")
                Picker("Sexo", selection: $sex) { ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                field("Edad", "años", $age, decimals: false)
                field("Altura", "cm", $height, decimals: false)
                field("Peso", "kg", $weight, decimals: true)
                if body_ == nil {
                    Text("Revisa los datos: edad 14–100, altura 120–230 cm, peso 30–300 kg.").font(.caption).foregroundStyle(DS.warn)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, _ unit: String, _ value: Binding<Double?>, decimals: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 16, weight: .semibold))
            Spacer()
            NumberField(placeholder: "0", value: value, decimals: decimals, width: 110)
            Text(unit).foregroundStyle(DS.text3).frame(width: 40, alignment: .leading)
        }
        .glass(padding: 12, radius: 16)
    }

    private var goalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tu objetivo").font(.display(28))
                ForEach(FitnessGoal.allCases) { g in
                    Button { goal = g; DS.haptic(.soft) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: g == .loseFat ? "flame.fill" : g == .gainMuscle ? "arrow.up.forward" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 18, weight: .bold)).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.label).font(.system(size: 17, weight: .bold))
                                Text(goalDetail(g)).font(.system(size: 12)).foregroundStyle(DS.text2)
                            }
                            Spacer()
                            if goal == g { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(DS.brandDiagonal) }
                        }
                        .foregroundStyle(DS.text)
                        .glass(padding: 14, radius: 18)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(goal == g ? DS.cyan : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                Text("Actividad").font(.system(size: 15, weight: .bold)).padding(.top, 8)
                Picker("Actividad", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(activity.detail).font(.footnote).foregroundStyle(DS.text2)
            }
            .padding(24)
        }
    }

    private func goalDetail(_ g: FitnessGoal) -> String {
        switch g {
        case .loseFat: return "−20 % de tu gasto, proteína alta para no perder músculo"
        case .gainMuscle: return "+10 % de tu gasto para construir sin coger grasa de más"
        case .recomposition: return "−10 %: perder grasa y ganar músculo a la vez"
        }
    }

    private var plan: some View {
        let t = body_.map(EnergyCalculator.targets(for:))
        return VStack(spacing: 20) {
            Spacer()
            Text("Tu plan").font(.display(28))
            ZStack {
                Ring(progress: shownKcal > 0 ? 1 : 0, lineWidth: 18, style: DS.brandDiagonal)
                VStack(spacing: 0) {
                    Text(NumberFormat.integer(shownKcal)).font(.number(40, .heavy)).contentTransition(.numericText())
                    Text("kcal al día").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.text2)
                }
            }
            .frame(width: 200, height: 200)
            if let t {
                HStack(spacing: 12) {
                    macro("Proteína", t.protein, DS.protein)
                    macro("Hidratos", t.carbs, DS.carbs)
                    macro("Grasa", t.fat, DS.fat)
                }
                .padding(.horizontal, 24)
                Text("Gasto estimado \(NumberFormat.integer(t.tdee)) kcal. Tu rutina de siempre ya está cargada en Entrenar, lista para editar.")
                    .font(.footnote).foregroundStyle(DS.text2).multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Spacer()
        }
        .onAppear {
            guard let t else { return }
            shownKcal = 0
            withAnimation(.easeOut(duration: 1.0)) { shownKcal = t.kcal }
        }
    }

    private func macro(_ name: String, _ g: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(g)) g").font(.number(20)).foregroundStyle(color)
            Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text2)
        }
        .frame(maxWidth: .infinity)
        .glass(padding: 12, radius: 16)
    }

    private func finish() {
        let p = Store.profile(context)
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.sexRaw = sex.rawValue
        p.age = Int(age ?? 30)
        p.heightCm = height ?? 175
        p.goalRaw = goal.rawValue
        p.activityRaw = activity.rawValue
        p.manualTargets = false
        p.onboarded = true
        if let w = weight { Store.logWeight(w, in: context) }
        p.recalculate(weightKg: weight)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onFinish()
    }
}
