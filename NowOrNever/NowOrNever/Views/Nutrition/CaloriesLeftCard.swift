import SwiftUI

/// Lo que te queda por comer hoy: objetivo − comido, en kcal y macros.
/// El color de las kcal dice en qué punto estás (azul, amarillo dorado, verde o rojo) y siempre va con un texto;
/// cada macro tiene su color fijo (proteínas coral, hidratos violeta, grasas turquesa).
struct CaloriesLeftCard: View {
    let consumed: NutritionValues
    let target: NutritionValues
    var title = "Hoy"
    /// Margen (± kcal) dentro del que el día cuenta como objetivo cumplido.
    var margin = CalorieStatus.defaultMargin
    /// Muestra el botón «Cambiar» para poner tú las calorías que quieres comer.
    var editable = true
    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let status = CalorieStatus.evaluate(consumed: consumed.kcal, target: target.kcal, margin: margin)
        let color = Theme.color(status)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if editable {
                    Button { editing = true } label: {
                        Label("Cambiar", systemImage: "pencil").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.lime)
                    .accessibilityIdentifier("kcal.edit")
                }
            }
            HStack(alignment: .center, spacing: 14) {
                ProgressRing(fraction: target.kcal > 0 ? consumed.kcal / target.kcal : 0, lineWidth: 8, size: 64,
                             label: "", color: color)
                    .overlay { Image(systemName: status.symbol).font(.title3.weight(.bold)).foregroundStyle(color) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(status)).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Text("\(NumberFormat.integer(bigNumber(status))) kcal")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("kcal.left")
                    Label(status.title, systemImage: status.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .accessibilityIdentifier("kcal.status")
                }
            }
            HStack(spacing: 0) {
                figure("Comido", consumed.kcal)
                figure("Objetivo", target.kcal)
                figure(remainingLabel(status), remainingValue(status))
            }
            .padding(.vertical, 8)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                ForEach(Macro.allCases, id: \.self) { m in
                    macro(m, m.value(consumed), m.value(target))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        // El color cambia con una transición suave al añadir, editar o quitar comida.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: status.kind)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: consumed.kcal)
        .sheet(isPresented: $editing) { TargetsEditorSheet() }
    }

    private func headline(_ status: CalorieStatus) -> String {
        switch status {
        case .plenty, .approaching: return "Te quedan"
        case .onTarget(let delta): return delta > 0 ? "Dentro del margen, por encima" : delta < 0 ? "Dentro del margen, te quedan" : "Justo en tu objetivo"
        case .over: return "Te has pasado"
        }
    }

    private func bigNumber(_ status: CalorieStatus) -> Double {
        switch status {
        case .plenty(let left), .approaching(let left): return left
        case .onTarget(let delta): return abs(delta)
        case .over(let excess): return excess
        }
    }

    private func remainingLabel(_ status: CalorieStatus) -> String {
        if case .over = status { return "Exceso" }
        return consumed.kcal > target.kcal ? "De más" : "Restantes"
    }

    private func remainingValue(_ status: CalorieStatus) -> Double {
        abs(target.kcal - consumed.kcal)
    }

    private func figure(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(NumberFormat.integer(value)).font(.subheadline.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func macro(_ m: Macro, _ eaten: Double, _ goal: Double) -> some View {
        let left = goal - eaten
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(m.color).frame(width: 7, height: 7)
                Text(m.name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("\(NumberFormat.integer(eaten))/\(NumberFormat.integer(goal)) g")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            // El exceso se dice con texto e icono; el color sigue siendo el del nutriente.
            Label(left >= 0 ? "quedan \(NumberFormat.integer(left)) g" : "\(NumberFormat.integer(-left)) g de más",
                  systemImage: left >= 0 ? "arrow.down.right" : "plus.circle.fill")
                .labelStyle(.titleOnly)
                .font(.caption2.weight(left >= 0 ? .regular : .bold))
                .foregroundStyle(left >= 0 ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            ProgressBar(fraction: goal > 0 ? eaten / goal : 0, color: m.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
