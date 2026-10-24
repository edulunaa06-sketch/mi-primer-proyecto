import SwiftUI

/// El anillo amarillo de calorías: en el centro, las que quedan hoy.
struct CalorieRing: View {
    let eaten: Double
    let target: Double
    var size: CGFloat = 230

    private var remaining: Double { target - eaten }
    private var exceeded: Bool { remaining < 0 }
    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, eaten / target))
    }

    private var ringColor: Color { exceeded ? Theme.danger : Theme.accent }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.cardElevated, lineWidth: 18)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor,
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.35), radius: 10)
                .animation(.easeOut(duration: 0.35), value: progress)

            VStack(spacing: 2) {
                Text(exceeded ? "TE HAS PASADO" : "TE QUEDAN")
                    .font(Theme.overline)
                    .kerning(1.6)
                    .foregroundStyle(exceeded ? Theme.danger : Theme.textSecondary)

                Text(Formatters.kcal(abs(remaining)))
                    .font(Theme.hero(size * 0.27))
                    .foregroundStyle(exceeded ? Theme.danger : Theme.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: remaining)

                Text("de \(Formatters.kcal(target)) kcal")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 30) {
        CalorieRing(eaten: 1240, target: 2200)
        CalorieRing(eaten: 2460, target: 2200, size: 180)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .screenBackground()
}
