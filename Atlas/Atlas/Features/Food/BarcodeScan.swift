import SwiftData
import SwiftUI
import VisionKit

/// Escanear el código de barras de un producto y traer sus valores de Open Food Facts (gratis, sin cuenta).
/// Si la cámara no está disponible, se puede escribir el número del código.
struct ScanFoodView: View {
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @State private var code = ""
    @State private var loading = false
    @State private var message: String?
    @State private var found: PickableFood?
    @State private var lastScanned = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if BarcodeScanner.isAvailable {
                    BarcodeScanner { scanned in
                        guard scanned != lastScanned, !loading else { return }
                        lastScanned = scanned
                        code = scanned
                        DS.haptic(.medium)
                        Task { await lookup() }
                    }
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DS.cyan.opacity(0.6), lineWidth: 2))
                } else {
                    EmptyHint(symbol: "barcode.viewfinder", title: "Escribe el código",
                              message: "La cámara no está disponible aquí. Escribe los números que hay bajo las barras.")
                }
                HStack {
                    TextField("Código de barras", text: $code)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surfaceHi))
                        .accessibilityIdentifier("scan.code")
                    Button("Buscar") { Task { await lookup() } }
                        .buttonStyle(.primaryCompact)
                        .disabled(OpenFoodFacts.url(barcode: code) == nil || loading)
                }
                if loading { ProgressView().tint(DS.cyan) }
                if let message { Text(message).font(.footnote).foregroundStyle(DS.text2).multilineTextAlignment(.center) }
                Text("Datos de Open Food Facts, una base de datos abierta. Revisa que coincidan con la etiqueta.")
                    .font(.caption2).foregroundStyle(DS.text3)
            }
        }
        .sheet(item: $found) { food in
            AmountSheet(food: food, meal: meal, dayKey: dayKey) { onDone() }
                .presentationDetents([.height(440)])
        }
    }

    private func lookup() async {
        guard let url = OpenFoodFacts.url(barcode: code) else { message = "El código debe tener entre 8 y 14 números."; return }
        loading = true
        defer { loading = false }
        message = nil
        do {
            var request = URLRequest(url: url)
            request.setValue("ATLAS iOS - personal fitness app", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let product = OpenFoodFacts.parse(data) else {
                message = "No está en la base de datos o no tiene calorías. Créalo tú en «Crear» con la etiqueta."
                return
            }
            // Se guarda como alimento tuyo para encontrarlo después sin escanear.
            let custom = CustomFood(name: product.name, per100: product.per100)
            context.insert(custom)
            try? context.save()
            found = PickableFood(id: "custom-\(custom.id)", name: product.name, per100: product.per100, note: "Escaneado")
        } catch {
            message = "Sin conexión. Inténtalo de nuevo o crea el alimento a mano."
        }
    }
}

/// Lector de códigos de barras con la cámara (VisionKit).
struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    @MainActor static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    onCode(value)
                    return
                }
            }
        }
    }
}
