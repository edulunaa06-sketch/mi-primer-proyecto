import SwiftData
import SwiftUI

/// El «+» de la barra: apuntar cualquier cosa desde cualquier pantalla, sin ir buscándola.
struct QuickAddSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showWeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Qué apuntamos?")
                .font(.display(22))
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("Comida", "fork.knife", Theme.carbs) { go(.nutrition) }
                tile("Entreno", "dumbbell.fill", DS.indigo) { go(.training) }
                tile("Peso", "scalemass.fill", DS.cyan) { showWeight = true }
                tile("Agua +250 ml", "drop.fill", DS.water) {
                    DataStore.changeWater(250, in: context)
                    DS.haptic(.light)
                    dismiss()
                }
                tile("Foto de progreso", "camera.fill", Theme.gold) { go(.progress) }
                tile("Calendario", "calendar", Theme.rest) { go(.calendar) }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtlasBackground())
        .presentationCornerRadius(28)
        .sheet(isPresented: $showWeight, onDismiss: { dismiss() }) { WeightEntrySheet() }
    }

    /// Cierra esta hoja y cambia de pestaña cuando ya se ha ido.
    private func go(_ tab: AppTab) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.tab = tab }
    }

    private func tile(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick.\(symbol)")
    }
}
