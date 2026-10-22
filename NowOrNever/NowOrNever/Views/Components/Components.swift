import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.lime)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var size: CGFloat = 84
    var label: String?

    var body: some View {
        ZStack {
            Circle().stroke(Theme.cardRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            Text(label ?? NumberFormat.percent(fraction))
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 8
    var color: Color = Theme.lime

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cardRaised)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Barra de macro: consumido / objetivo.
struct MacroRow: View {
    let name: String
    let consumed: Double
    let target: Double
    var unit = "g"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(NumberFormat.integer(consumed)) / \(NumberFormat.integer(target)) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            ProgressBar(fraction: NutritionMath.progress(consumed: consumed, target: target))
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(Theme.lime).font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .card(padding: 14)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct CheckCircle: View {
    let isOn: Bool
    var size: CGFloat = 26
    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundStyle(isOn ? Theme.lime : Theme.textTertiary)
            .contentTransition(.symbolEffect(.replace))
    }
}

struct InfoBanner: View {
    let text: String
    var symbol = "info.circle.fill"
    var color: Color = Theme.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Campo numérico que acepta coma decimal y se vincula a un Double opcional.
struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double?
    var width: CGFloat? = nil

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: width)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: value) { _, newValue in
                if !focused { text = Self.format(newValue) }
            }
            .onChange(of: text) { _, newText in
                let parsed = NumberFormat.parseDecimal(newText)
                if newText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if value != nil { value = nil }
                } else if let parsed, parsed >= 0, parsed != value {
                    value = parsed
                }
            }
    }

    static func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return NumberFormat.oneDecimal(v)
    }
}

/// Campo de enteros (repeticiones).
struct IntField: View {
    let placeholder: String
    @Binding var value: Int?
    var width: CGFloat? = nil

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(width: width)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .focused($focused)
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: value) { _, newValue in
                if !focused { text = newValue.map(String.init) ?? "" }
            }
            .onChange(of: text) { _, newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if value != nil { value = nil }
                } else if let parsed = Int(trimmed), parsed >= 0, parsed != value {
                    value = parsed
                }
            }
    }
}
