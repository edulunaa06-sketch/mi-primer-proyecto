import PhotosUI
import SwiftUI
import UIKit

/// «Foto del plato»: haces una foto, pones lo que pesa la comida y Claude ve qué hay (pollo, boniato,
/// queso cottage…), reparte el peso y calcula kcal y macros. Si duda de algún alimento te pregunta,
/// respondes y recalcula.
struct PhotoMealCard: View {
    let type: MealType
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(ClaudeService.self) private var claude

    @State private var jpeg: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var foodGrams: Double?
    @State private var plateGrams: Double?
    @State private var comment = ""
    @State private var analysis: ClaudeAPI.PhotoAnalysis?
    @State private var raw: String?
    @State private var answers: [String] = []
    @State private var removed: Set<Int> = []
    @State private var error: String?

    /// Peso de la comida: si das el del plato vacío, se resta.
    private var netGrams: Double? {
        guard let foodGrams, foodGrams > 0 else { return nil }
        let net = foodGrams - (plateGrams ?? 0)
        return net > 0 ? net : nil
    }

    private var keptItems: [ClaudeAPI.EstimatedItem] {
        (analysis?.items ?? []).enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Foto del plato", subtitle: "Haz una foto, pesa la comida y Claude calcula las kcal")
            photoArea
            HStack(spacing: 10) {
                field("Peso en báscula (g)", value: $foodGrams, id: "photo.grams")
                field("Plato vacío (g, opcional)", value: $plateGrams, id: "photo.plate")
            }
            if let foodGrams, let plateGrams, plateGrams > 0 {
                Text(netGrams.map { "Comida: \(NumberFormat.integer($0)) g (\(NumberFormat.integer(foodGrams)) − \(NumberFormat.integer(plateGrams)) del plato)" }
                     ?? "El plato vacío no puede pesar más que el total.")
                    .font(.caption).foregroundStyle(netGrams == nil ? Theme.danger : Theme.textSecondary)
            }
            TextField("Comentario opcional (ej.: «el pollo lleva salsa de yogur»)", text: $comment, axis: .vertical)
                .lineLimit(1...3)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !claude.isConfigured {
                InfoBanner(text: "Para analizar fotos añade tu clave de la API de Claude en Ajustes › Claude (IA).")
            }
            Button {
                Task { await analyze(answering: false) }
            } label: {
                if claude.isWorking { ProgressView().tint(.black) } else { Label(analysis == nil ? "Calcular con la foto" : "Volver a analizar", systemImage: "camera.viewfinder") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(jpeg == nil || netGrams == nil || claude.isWorking || !claude.isConfigured)
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            if let analysis { result(analysis) }
        }
        .card()
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setImage(data) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SystemCamera { data in setImage(data) }.ignoresSafeArea()
        }
    }

    private var photoArea: some View {
        HStack(spacing: 10) {
            if let jpeg, let image = UIImage(data: jpeg) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(spacing: 8) {
                Button { showCamera = true } label: { Label("Hacer foto", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LimeButtonStyle(filled: jpeg == nil))
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Elegir de la galería", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle(filled: false))
            }
        }
    }

    @ViewBuilder
    private func result(_ analysis: ClaudeAPI.PhotoAnalysis) -> some View {
        if analysis.items.isEmpty {
            Text(analysis.note.isEmpty ? "Claude no ha reconocido comida en la foto." : analysis.note)
                .font(.footnote).foregroundStyle(Theme.warning)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lo que ve Claude").font(.headline)
                ForEach(Array(analysis.items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline).strikethrough(removed.contains(index))
                            Text("\(NumberFormat.integer(item.grams)) g · \(NumberFormat.integer(item.kcalPer100g)) kcal/100 g · P \(NumberFormat.oneDecimal(item.values.protein)) g")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("≈ \(NumberFormat.integer(item.values.kcal)) kcal").font(.subheadline.monospacedDigit())
                        Button {
                            if removed.contains(index) { removed.remove(index) } else { removed.insert(index) }
                        } label: {
                            Image(systemName: removed.contains(index) ? "arrow.uturn.backward.circle" : "xmark.circle")
                                .foregroundStyle(removed.contains(index) ? Theme.lime : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(removed.contains(index) ? "Volver a incluir \(item.name)" : "Quitar \(item.name)")
                    }
                }
                let total = NutritionMath.sum(keptItems.map(\.values))
                Text("Total: \(NumberFormat.integer(total.kcal)) kcal · P \(NumberFormat.integer(total.protein)) g · C \(NumberFormat.integer(total.carbs)) g · G \(NumberFormat.integer(total.fat)) g")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.lime)
                    .accessibilityIdentifier("photo.total")
                if !analysis.note.isEmpty {
                    Text(analysis.note).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            if !analysis.questions.isEmpty { questions(analysis.questions) }
            Button("Añadir a mi \(type.label.lowercased())") { addToMeal() }
                .buttonStyle(LimeButtonStyle(filled: analysis.questions.isEmpty))
                .disabled(keptItems.isEmpty)
        }
    }

    private func questions(_ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude tiene dudas", systemImage: "questionmark.bubble.fill")
                .font(.headline).foregroundStyle(Theme.warning)
            Text("Responde para afinar el cálculo (o añádelo tal cual si te vale la estimación).")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            ForEach(Array(list.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 4) {
                    Text(question).font(.subheadline.weight(.semibold))
                    TextField("Tu respuesta", text: Binding(
                        get: { index < answers.count ? answers[index] : "" },
                        set: { value in
                            while answers.count <= index { answers.append("") }
                            answers[index] = value
                        }))
                        .padding(8)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Button {
                Task { await analyze(answering: true) }
            } label: {
                if claude.isWorking { ProgressView() } else { Label("Responder y recalcular", systemImage: "arrow.clockwise") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(claude.isWorking || answers.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        .padding(12)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func field(_ title: String, value: Binding<Double?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            DecimalField(placeholder: "0", value: value, width: nil)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setImage(_ data: Data) {
        jpeg = Self.preparedJPEG(data)
        analysis = nil
        raw = nil
        answers = []
        removed = []
        error = jpeg == nil ? "No se pudo leer la imagen." : nil
    }

    private func analyze(answering: Bool) async {
        guard let jpeg, let grams = netGrams else { return }
        error = nil
        var pairs: [ClaudeAPI.Answer] = []
        if answering, let questions = analysis?.questions {
            pairs = questions.enumerated().compactMap { index, question in
                let answer = index < answers.count ? answers[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return answer.isEmpty ? nil : ClaudeAPI.Answer(question: question, answer: answer)
            }
        }
        do {
            let result = try await claude.analyzePhoto(jpeg: jpeg, totalGrams: grams, comment: comment,
                                                       previous: answering ? raw : nil, answers: pairs)
            analysis = result.analysis
            raw = result.raw
            answers = []
            removed = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addToMeal() {
        for item in keptItems {
            DataStore.addCustomItem(type, name: item.name, grams: item.grams, per100: item.per100,
                                    source: .claude, on: day, in: context)
        }
        analysis = nil
        raw = nil
        jpeg = nil
        foodGrams = nil
        plateGrams = nil
        comment = ""
    }

    /// Reduce la foto (lado mayor 1568 px, JPEG 80 %): suficiente para reconocer la comida y mucho más rápida de enviar.
    static func preparedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1568
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// Cámara del sistema para la foto del plato.
struct SystemCamera: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SystemCamera
        init(_ parent: SystemCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
