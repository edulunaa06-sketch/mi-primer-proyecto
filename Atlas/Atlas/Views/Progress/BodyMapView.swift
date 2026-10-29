import SwiftData
import SwiftUI

/// El cuerpo por músculos, de frente y de espalda, con el rango de cada uno.
///
/// Lo que colorea cada músculo es TU trabajo registrado: las series que le has dedicado,
/// repartidas en semanas, y cuánto han subido tus pesos. La pantalla lo dice tal cual:
/// no mide tu músculo, mide lo que has apuntado.
struct BodyMapView: View {
    @Environment(\.modelContext) private var context

    /// No se usa para pintar: está para recalcular los rangos en cuanto te creas un ejercicio
    /// (cambia a qué músculo va lo que apuntas). Es una tabla pequeña.
    @Query private var mine: [CustomExercise]

    @State private var side: BodyMap.Side = .front
    @State private var selected: MuscleGroup?
    @State private var statuses: [MuscleLevel.Status] = []

    private var byGroup: [MuscleGroup: MuscleLevel.Status] {
        Dictionary(statuses.map { ($0.group, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Lado", selection: $side) {
                    ForEach(BodyMap.Side.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                bodyCard
                if let selected, let status = byGroup[selected] {
                    detailCard(status)
                }
                summaryCard
                listCard
                InfoBanner(text: "El rango sale de lo que has apuntado en la app: series directas de cada músculo, "
                           + "repartidas en semanas, y cuánto han subido tus pesos. No mide tu músculo ni te compara "
                           + "con nadie: si entrenas y no lo apuntas, aquí no cuenta.")
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Cuerpo y rangos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .task(id: mine.count) { reload() }
        .accessibilityIdentifier("bodymap")
    }

    private func reload() {
        statuses = StrengthStore.muscleLevels(in: context)
    }

    // MARK: El dibujo

    private var bodyCard: some View {
        VStack(spacing: 10) {
            BodyDrawing(side: side, color: { group in rankColor(byGroup[group]?.rank) },
                        selected: selected, onTap: { group in
                            DS.haptic(.light)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selected = (selected == group) ? nil : group
                            }
                        })
                // El alto manda: con solo el ancho, el cuerpo salía de 320 x 688 y empujaba
                // el resumen y la lista fuera de la pantalla.
                .frame(maxWidth: 320, maxHeight: 420)
                .frame(maxWidth: .infinity)
            Text(selected == nil ? "Toca un músculo para ver su rango." : "Toca otro para cambiar.")
                .font(.caption).foregroundStyle(Theme.textTertiary)
            legend
        }
        .card()
    }

    private var legend: some View {
        HStack(spacing: 6) {
            ForEach(MuscleLevel.Rank.allCases) { rank in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(rankColor(rank))
                        .frame(height: 6)
                    Text(rank.label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }

    // MARK: Fichas

    private func detailCard(_ status: MuscleLevel.Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.group.label).font(.headline)
                    Text(status.rank.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(rankColor(status.rank))
                }
                Spacer()
                if let next = status.nextRank {
                    Text("Siguiente: \(next.label)")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            ProgressView(value: status.progress)
                .tint(rankColor(status.rank))
            HStack {
                stat("Series directas", NumberFormat.oneDecimal(status.directSets))
                stat("Semanas", "\(status.weeksTrained)")
                stat("Kilos movidos", NumberFormat.integer(status.tonnageKg) + " kg")
            }
            if status.strengthBonus > 0 {
                Label("Tus pesos han subido: +\(NumberFormat.percent(status.strengthBonus)) de puntos.",
                      systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            Text(status.advice).font(.caption).foregroundStyle(Theme.textSecondary)
            NavigationLink {
                ExerciseLibraryView()
            } label: {
                Label("Ejercicios para \(status.group.label.lowercased())", systemImage: "books.vertical.fill")
                    .font(.caption.weight(.semibold))
            }
        }
        .card()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryCard: some View {
        let trained = statuses.filter { $0.directSets > 0 }
        let weak = MuscleLevel.weakest(statuses)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "De un vistazo",
                          subtitle: trained.isEmpty ? "Todavía no hay series apuntadas" : nil)
            if trained.isEmpty {
                Text("Apunta las series de un entrenamiento y este cuerpo empezará a encenderse.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Con series apuntadas: \(trained.count) de \(statuses.count) músculos.")
                    .font(.subheadline)
                Text("Los que menos trabajo llevan: " + weak.map { $0.group.label.lowercased() }.joined(separator: ", ") + ".")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Todos los músculos", subtitle: "Ordenados por lo que llevas trabajado")
            ForEach(statuses.sorted { a, b in
                a.points == b.points ? a.group.sortIndex < b.group.sortIndex : a.points > b.points
            }) { status in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = status.group
                        if !BodyMap.visibleMuscles(side).contains(status.group) { side = side.other }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(rankColor(status.rank)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.group.label).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Text("\(NumberFormat.oneDecimal(status.directSets)) series · \(status.rank.label)")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        ProgressView(value: status.progress)
                            .tint(rankColor(status.rank))
                            .frame(width: 70)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    /// Color de cada rango: del grafito del músculo que no has tocado al champán del máximo,
    /// pasando por el platino y el oro. La idea es que se vea de un vistazo lo que te falta.
    private func rankColor(_ rank: MuscleLevel.Rank?) -> Color {
        switch rank {
        case .none, .some(.novato): return Color(red: 0.16, green: 0.15, blue: 0.14)
        case .some(.iniciado): return DS.steel.opacity(0.40)
        case .some(.intermedio): return DS.steel
        case .some(.avanzado): return DS.goldDark
        case .some(.veterano): return DS.gold
        case .some(.elite): return DS.champagne
        }
    }
}

// MARK: - El cuerpo dibujado

/// Dibuja la silueta y encima cada músculo con su color. Los músculos se pueden tocar.
struct BodyDrawing: View {
    let side: BodyMap.Side
    let color: (MuscleGroup) -> Color
    var selected: MuscleGroup?
    var onTap: ((MuscleGroup) -> Void)?

    var body: some View {
        ZStack {
            ForEach(BodyMap.silhouettePieces) { piece in
                MusclePolygon(points: piece.points)
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
            }
            ForEach(BodyMap.pieces(side)) { piece in
                if let group = piece.group {
                    MusclePolygon(points: piece.points)
                        .fill(color(group))
                        .overlay(
                            MusclePolygon(points: piece.points)
                                .stroke(selected == group ? Color.white : Color.black.opacity(0.55),
                                        lineWidth: selected == group ? 2 : 1)
                        )
                        .contentShape(MusclePolygon(points: piece.points))
                        .onTapGesture { onTap?(group) }
                        .accessibilityLabel(group.label)
                }
            }
        }
        .aspectRatio(BodyMap.aspect, contentMode: .fit)
        .animation(.easeInOut(duration: 0.25), value: side)
    }
}

/// Un músculo: el polígono de `BodyMap` con las esquinas redondeadas, para que no parezca
/// un cristal roto.
struct MusclePolygon: Shape {
    let points: [BodyMap.Point]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }
        let pts = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        path.move(to: mid(pts[0], pts[1]))
        for index in 1...pts.count {
            let current = pts[index % pts.count]
            let next = pts[(index + 1) % pts.count]
            path.addQuadCurve(to: mid(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }
}
