import AVFoundation
import SwiftData
import SwiftUI
import UIKit

/// Escanear el código de barras de un alimento: la cámara lo lee, se busca el producto y
/// aparece con sus calorías por 100 g. Tú pones los gramos y la app calcula lo que llevas.
///
/// Reglas de la casa:
///  · Lo escaneado se guarda en tu catálogo, así que la segunda vez funciona sin internet.
///  · Los datos de Open Food Facts los suben voluntarios: salen marcados como provisionales
///    y puedes corregirlos con la etiqueta antes de apuntarlos.
///  · Si el producto no está, no se inventa nada: se apunta a mano y queda guardado con su código.
struct BarcodeScannerView: View {
    let type: MealType
    let day: Date
    var onAdded: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = BarcodeScanner()
    @State private var lookup = BarcodeLookup()
    @State private var typed = ""
    @State private var state: Step = .scanning
    @State private var grams: Double? = 100
    @State private var editing = false
    @State private var editName = ""
    @State private var editKcal: Double?
    @State private var editProtein: Double?
    @State private var editCarbs: Double?
    @State private var editFat: Double?

    private enum Step: Equatable {
        case scanning
        case searching(String)
        /// Producto listo para apuntar. `fromCatalog` = ya lo tenías guardado (sin internet).
        case product(ScannedFood, fromCatalog: Bool)
        case problem(String, barcode: String)
    }

    /// Lo que se va a apuntar, venga del catálogo o de Open Food Facts.
    struct ScannedFood: Equatable {
        let barcode: String
        var name: String
        var brand: String
        var per100: NutritionValues
        var missingMacros: [String]
        var note: String

        var title: String {
            let parts = [brand, name].filter { !$0.isEmpty }
            return parts.isEmpty ? barcode : parts.joined(separator: " · ")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch state {
                    case .scanning:
                        cameraCard
                        manualCard
                    case .searching(let code):
                        searchingCard(code)
                    case .product(let food, let fromCatalog):
                        productCard(food, fromCatalog: fromCatalog)
                    case .problem(let message, let barcode):
                        problemCard(message, barcode: barcode)
                    }
                    InfoBanner(text: "Los datos vienen de Open Food Facts, una base abierta que mantienen voluntarios. "
                               + "Si no cuadran con la etiqueta, corrígelos antes de añadirlo: se guardan corregidos para la próxima vez.")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Escanear · \(type.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .task { await scanner.start() }
            .onDisappear { scanner.stop() }
            .onChange(of: scanner.code) { _, code in
                guard let code, case .scanning = state else { return }
                DS.haptic(.heavy)
                Task { await resolve(code) }
            }
        }
    }

    // MARK: Cámara

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Apunta al código de barras",
                          subtitle: "Encaja el código dentro del recuadro. Se lee solo.")
            ZStack {
                switch scanner.state {
                case .denied:
                    scannerMessage("Now or Never no tiene permiso para usar la cámara. Actívalo en Ajustes › Now or Never › Cámara, o escribe el código a mano aquí abajo.")
                case .unavailable:
                    scannerMessage("Este dispositivo no tiene cámara disponible (por ejemplo, el simulador). Escribe el código a mano aquí abajo.")
                case .starting:
                    ProgressView().tint(Theme.lime).frame(maxWidth: .infinity, minHeight: 180)
                case .running:
                    BarcodePreview(session: scanner.session)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.lime, lineWidth: 3)
                                .frame(height: 110)
                                .padding(.horizontal, 24)
                        )
                }
            }
            .accessibilityIdentifier("barcode.camera")
        }
        .card()
    }

    private func scannerMessage(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "O escribe el código", subtitle: "Los números de debajo de las barras")
            HStack {
                TextField("8410076472014", text: $typed)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("barcode.field")
                Button("Buscar") { Task { await resolve(typed) } }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(!OpenFoodFacts.isPlausible(typed))
            }
            Divider().overlay(Theme.separator)
            Text("¿Sin código de barras, o no sale en la base? Ponlo tú con la etiqueta: "
                 + "queda guardado en tus alimentos y la próxima vez solo pones los gramos.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            Button("Apuntarlo a mano y guardarlo") { startManualEntry(barcode: typed) }
                .buttonStyle(LimeButtonStyle(filled: false))
                .accessibilityIdentifier("barcode.manual")
        }
        .card()
    }

    private func searchingCard(_ code: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.lime)
            Text("Buscando \(code)…").font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: Producto encontrado

    private func productCard(_ food: ScannedFood, fromCatalog: Bool) -> some View {
        let per100 = editing ? editedValues(food) : food.per100
        let total = per100.scaled(toGrams: grams ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editing && !editName.isEmpty ? editName : food.title)
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Text(subtitle(food, fromCatalog: fromCatalog))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Divider().overlay(Theme.separator)

            if editing {
                Text("Pon el nombre y los valores de la etiqueta, por 100 g.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                TextField("Nombre (p. ej. tortitas de arroz)", text: $editName)
                    .padding(10)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("barcode.name")
                labeled("Kcal / 100 g", $editKcal)
                labeled("Proteínas / 100 g", $editProtein)
                labeled("Carbohidratos / 100 g", $editCarbs)
                labeled("Grasas / 100 g", $editFat)
            } else {
                HStack {
                    Text("Por 100 g").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(NumberFormat.integer(per100.kcal)) kcal")
                        .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.lime)
                }
                Text("P \(NumberFormat.oneDecimal(per100.protein)) g · C \(NumberFormat.oneDecimal(per100.carbs)) g · G \(NumberFormat.oneDecimal(per100.fat)) g")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                if !food.missingMacros.isEmpty {
                    Text("Sin datos de \(food.missingMacros.joined(separator: ", ")): se apuntan como 0. Corrígelo con la etiqueta si te importa el macro.")
                        .font(.caption2).foregroundStyle(Theme.warning)
                }
            }

            Divider().overlay(Theme.separator)
            HStack {
                Text("¿Cuántos gramos comes?").font(.subheadline)
                Spacer()
                DecimalField(placeholder: "g", value: $grams, width: 90)
            }
            Text("≈ \(NumberFormat.integer(total.kcal)) kcal · P \(NumberFormat.oneDecimal(total.protein)) · C \(NumberFormat.oneDecimal(total.carbs)) · G \(NumberFormat.oneDecimal(total.fat))")
                .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.lime)

            Button("Añadir a mi \(type.label.lowercased())") { add(food, per100: per100) }
                .buttonStyle(LimeButtonStyle())
                .disabled((grams ?? 0) <= 0 || !hasUsableName(food) || per100.kcal <= 0)
                .accessibilityIdentifier("barcode.add")
            if editing && !hasUsableName(food) {
                Text("Ponle un nombre para poder guardarlo.")
                    .font(.caption2).foregroundStyle(Theme.warning)
            }
            HStack(spacing: 12) {
                if !(editing && food.per100.kcal <= 0) {
                    Button(editing ? "Dejar los datos de Open Food Facts" : "Corregir con la etiqueta") {
                        if !editing { startEditing(food) }
                        editing.toggle()
                    }
                    .font(.caption.weight(.semibold))
                }
                Spacer()
                Button("Escanear otro") { reset() }.font(.caption.weight(.semibold))
            }
        }
        .card()
    }

    private func labeled(_ title: String, _ binding: Binding<Double?>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            DecimalField(placeholder: "0", value: binding, width: 90)
        }
    }

    private func problemCard(_ message: String, barcode: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No se ha podido usar ese código", systemImage: "barcode.viewfinder")
                .font(.headline).foregroundStyle(Theme.warning)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Button(OpenFoodFacts.isPlausible(barcode)
                   ? "Apuntarlo a mano y guardarlo con su código"
                   : "Apuntarlo a mano y guardarlo") {
                startManualEntry(barcode: barcode)
            }
            .buttonStyle(LimeButtonStyle())
            Button("Volver a escanear") { reset() }
                .buttonStyle(LimeButtonStyle(filled: false))
        }
        .card()
    }

    // MARK: Acciones

    private func resolve(_ rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OpenFoodFacts.isPlausible(code) else {
            state = .problem(OpenFoodFacts.LookupError.badBarcode(code).message, barcode: code)
            return
        }
        // Primero lo tuyo: si ya lo escaneaste alguna vez, no hace falta internet.
        if let saved = DataStore.food(withBarcode: code, in: context) {
            grams = saved.lastGrams > 0 ? saved.lastGrams : 100
            state = .product(ScannedFood(barcode: code, name: saved.name, brand: saved.brand,
                                         per100: saved.per100, missingMacros: [],
                                         note: saved.sourceNote), fromCatalog: true)
            return
        }
        state = .searching(code)
        switch await lookup.lookup(code) {
        case .found(let product):
            grams = 100
            state = .product(ScannedFood(barcode: product.barcode, name: product.name, brand: product.brand,
                                         per100: product.per100, missingMacros: product.missingMacros,
                                         note: "Open Food Facts · \(product.barcode)"), fromCatalog: false)
        case .failed(let error):
            state = .problem(error.message, barcode: code)
        }
    }

    /// Rótulo de debajo del nombre: de dónde salen los datos que se ven.
    private func subtitle(_ food: ScannedFood, fromCatalog: Bool) -> String {
        let origin: String
        if editing { origin = "Lo pones tú, con la etiqueta" }
        else if fromCatalog { origin = "Ya lo tenías guardado" }
        else { origin = "Open Food Facts" }
        return food.barcode.isEmpty ? origin : "\(origin) · \(food.barcode)"
    }

    /// Hay nombre con el que guardarlo (el de la base, o el que escribes tú).
    private func hasUsableName(_ food: ScannedFood) -> Bool {
        if editing { return !editName.trimmingCharacters(in: .whitespaces).isEmpty }
        return !food.name.isEmpty
    }

    /// Apuntar un producto que no está en ningún sitio: pantalla en blanco, la rellenas tú.
    /// `barcode` puede ir vacío: hay cosas que ni código llevan (la fruta a granel, el pan).
    private func startManualEntry(barcode rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = OpenFoodFacts.isPlausible(code) ? code : ""
        let blank = ScannedFood(barcode: valid, name: "", brand: "", per100: .zero,
                                missingMacros: [], note: "Apuntado por ti")
        grams = 100
        startEditing(blank)
        editing = true
        state = .product(blank, fromCatalog: false)
    }

    private func startEditing(_ food: ScannedFood) {
        editName = food.name
        editKcal = food.per100.kcal > 0 ? food.per100.kcal : nil
        editProtein = food.per100.protein > 0 ? food.per100.protein : nil
        editCarbs = food.per100.carbs > 0 ? food.per100.carbs : nil
        editFat = food.per100.fat > 0 ? food.per100.fat : nil
    }

    private func editedValues(_ food: ScannedFood) -> NutritionValues {
        NutritionValues(kcal: editKcal ?? food.per100.kcal, protein: editProtein ?? food.per100.protein,
                        carbs: editCarbs ?? food.per100.carbs, fat: editFat ?? food.per100.fat)
    }

    private func add(_ food: ScannedFood, per100: NutritionValues) {
        guard let g = grams, g > 0 else { return }
        let typedName = editName.trimmingCharacters(in: .whitespaces)
        let foodName = editing && !typedName.isEmpty ? typedName : food.name
        guard !foodName.isEmpty else { return }
        // El nombre que se ve en la comida lleva la marca delante cuando la hay.
        let lineName = food.brand.isEmpty ? foodName : "\(food.brand) · \(foodName)"
        let source = editing
            ? (food.barcode.isEmpty ? "Etiqueta (lo has puesto tú)" : "Etiqueta (lo has puesto tú) · \(food.barcode)")
            : food.note
        let saved = DataStore.saveScanned(barcode: food.barcode, name: foodName,
                                          brand: food.brand, per100: per100,
                                          source: source, in: context)
        if editing {
            saved.isUserEdited = true
            saved.isProvisional = false
        }
        DataStore.recordUse(of: saved, grams: g, in: context)
        DataStore.addCustomItem(type, name: lineName, grams: g, per100: per100,
                                source: .catalog, on: day, in: context)
        DS.haptic(.medium)
        onAdded()
        dismiss()
    }

    private func reset() {
        editing = false
        editName = ""
        grams = 100
        scanner.resume()
        state = .scanning
    }
}

// MARK: - La cámara leyendo códigos

/// Sesión de AVFoundation configurada para leer códigos de barras de productos.
@Observable
final class BarcodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    enum State { case starting, running, denied, unavailable }

    var state: State = .starting
    /// Último código leído. La vista lo observa y busca el producto.
    var code: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCaptureMetadataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "NowOrNever.barcode")

    /// Los formatos que llevan los alimentos en España y en casi todo el mundo.
    static let formats: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        default:
            state = .denied
            return
        }
        guard configure() else { state = .unavailable; return }
        let session = session
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { session.startRunning(); done.resume() }
        }
        state = .running
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Vuelve a leer después de haber resuelto un código.
    @MainActor
    func resume() { code = nil }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }
        output.setMetadataObjectsDelegate(self, queue: queue)
        // Los tipos solo se pueden pedir DESPUÉS de añadir la salida a la sesión.
        output.metadataObjectTypes = Self.formats.filter { output.availableMetadataObjectTypes.contains($0) }
        return !output.metadataObjectTypes.isEmpty
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = object.stringValue, OpenFoodFacts.isPlausible(value) else { return }
        DispatchQueue.main.async {
            guard self.code == nil else { return }
            self.code = value
        }
    }
}

private struct BarcodePreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
