import SwiftData
import SwiftUI

/// El «+» de la barra: apuntar cualquier cosa desde cualquier pantalla, sin ir buscándola.
struct QuickAddSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showWeight = false
    @State private var showScanner = false
    @State private var showExtra = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Qué apuntamos?")
                .font(.display(22))
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("Comida", "fork.knife", Theme.carbs) { go(.nutrition) }
                tile("Escanear alimento", "barcode.viewfinder", DS.champagne) { showScanner = true }
                tile("Extra (cerveza, snack…)", "takeoutbag.and.cup.and.straw.fill", Theme.fat) { showExtra = true }
                tile("Entreno", "dumbbell.fill", DS.gold) { go(.training) }
                tile("Peso", "scalemass.fill", DS.steel) { showWeight = true }
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
        // Lo que te comes fuera de las comidas se apunta desde aquí sin dar un rodeo.
        .sheet(isPresented: $showScanner, onDismiss: { dismiss() }) {
            BarcodeScannerView(type: .extra, day: Date()) { syncExtras() }
        }
        .sheet(isPresented: $showExtra, onDismiss: { dismiss() }) {
            CustomMealSheet(type: .extra, day: Date(), target: .zero) { syncExtras() }
        }
    }

    /// Deja el día al tanto de los extras apuntados (cuentan en las calorías en cuanto se apuntan).
    private func syncExtras() {
        let items = DataStore.customItems(for: .extra, on: Date(), in: context)
        DataStore.setMeal(.extra, values: NutritionMath.sum(items.map(\.values)), planName: "Extras",
                          completed: !items.isEmpty, on: Date(), in: context)
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
