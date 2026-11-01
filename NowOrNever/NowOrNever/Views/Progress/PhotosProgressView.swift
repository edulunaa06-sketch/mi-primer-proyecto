import PhotosUI
import SwiftData
import SwiftUI

/// Fotos mensuales (frente, lateral, espalda). Se guardan solo en el iPhone.
/// El selector de fotos del sistema (PhotosPicker) no requiere permiso de acceso a toda la fototeca.
struct PhotosProgressView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProgressPhoto.year, order: .reverse), SortDescriptor(\ProgressPhoto.month, order: .reverse)])
    private var photos: [ProgressPhoto]

    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var targetView: PhotoView?
    @State private var actionView: PhotoView?
    @State private var viewing: ProgressPhoto?
    @State private var errorMessage: String?
    @State private var confirmDeleteAll = false
    @State private var isSaving = false
    @State private var sourceView: PhotoView?
    @State private var cameraView: PhotoView?

    private let current = DateUtils.yearMonth(Date())

    private var currentMonthPhotos: [PhotoView: ProgressPhoto] {
        Dictionary(photos.filter { $0.year == current.year && $0.month == current.month }.map { ($0.view, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    private var pastMonths: [(year: Int, month: Int)] {
        var seen = Set<String>()
        var result: [(year: Int, month: Int)] = []
        for p in photos where !(p.year == current.year && p.month == current.month) {
            let k = "\(p.year)-\(p.month)"
            if seen.insert(k).inserted { result.append((year: p.year, month: p.month)) }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                currentMonthCard
                if !pastMonths.isEmpty || !currentMonthPhotos.isEmpty {
                    NavigationLink {
                        PhotoCompareView()
                    } label: {
                        Label("Antes / después", systemImage: "square.split.2x1")
                    }
                    .buttonStyle(LimeButtonStyle(filled: false))
                }
                pastMonthsCard
                privacyCard
            }
            .padding(16)
        }
        .screenBackground()
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let view = targetView else { return }
            Task { await save(item, view: view) }
        }
        .confirmationDialog(actionView.map { "Foto de \($0.label.lowercased())" } ?? "",
                            isPresented: Binding(get: { actionView != nil }, set: { if !$0 { actionView = nil } }),
                            titleVisibility: .visible) {
            if let view = actionView {
                Button("Ver foto") { viewing = currentMonthPhotos[view] }
                Button("Repetir con la cámara") { cameraView = view }
                Button("Reemplazar con una de la galería") { targetView = view; showPicker = true }
                Button("Eliminar foto", role: .destructive) { delete(currentMonthPhotos[view]) }
            }
        } message: {
            Text("Ya hay una foto para este mes. Reemplazarla borrará la anterior.")
        }
        .confirmationDialog("¿Eliminar TODAS las fotos de progreso?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Eliminar todo el historial de fotos", role: .destructive) {
                do { try PhotoStorage.deleteAll(in: context) } catch { errorMessage = error.localizedDescription }
            }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
        .confirmationDialog(sourceView.map { "Foto de \($0.label.lowercased())" } ?? "",
                            isPresented: Binding(get: { sourceView != nil }, set: { if !$0 { sourceView = nil } }),
                            titleVisibility: .visible) {
            if let view = sourceView {
                Button("Hacer foto con la cámara") { cameraView = view }
                Button("Elegir de la galería") { targetView = view; showPicker = true }
            }
        }
        .fullScreenCover(item: $cameraView) { view in
            CameraCaptureView(view: view, guide: previousPhoto(view).flatMap { PhotoStorage.image($0.fileName, maxPixel: 1600) }) { data in
                saveData(data, view: view)
            }
        }
        .fullScreenCover(item: $viewing) { PhotoViewer(photo: $0) }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var currentMonthCard: some View {
        let missing = PhotoView.allCases.filter { currentMonthPhotos[$0] == nil }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: DateUtils.monthTitle(year: current.year, month: current.month),
                          subtitle: missing.isEmpty ? "¡Las tres vistas están completas!" : "Faltan: " + missing.map(\.label).joined(separator: ", "))
            HStack(spacing: 10) {
                ForEach(PhotoView.allCases) { view in
                    slot(view)
                }
            }
            if isSaving { ProgressView("Guardando…").font(.caption) }
        }
        .card()
    }

    private func slot(_ view: PhotoView) -> some View {
        let photo = currentMonthPhotos[view]
        return Button {
            if photo == nil {
                sourceView = view
            } else {
                actionView = view
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardRaised)
                    if let photo, let image = PhotoStorage.image(photo.fileName, maxPixel: 400) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "plus.viewfinder").font(.title2).foregroundStyle(Theme.lime)
                    }
                }
                .frame(height: 140)
                .clipped()
                HStack(spacing: 4) {
                    Image(systemName: photo == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .foregroundStyle(photo == nil ? Theme.textTertiary : Theme.lime)
                    Text(view.label).font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var pastMonthsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Meses anteriores")
            if pastMonths.isEmpty {
                Text("Aún no hay fotos de meses anteriores.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(pastMonths.enumerated()), id: \.offset) { _, ym in
                NavigationLink {
                    MonthPhotosView(year: ym.year, month: ym.month)
                } label: {
                    HStack {
                        Text(DateUtils.monthTitle(year: ym.year, month: ym.month))
                        Spacer()
                        let count = photos.filter { $0.year == ym.year && $0.month == ym.month }.count
                        Text("\(count)/3").foregroundStyle(count == 3 ? Theme.lime : Theme.textSecondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Privacidad", systemImage: "lock.fill").font(.headline)
            Text("Las fotos se guardan cifradas por iOS dentro de Now or Never, solo en este iPhone. La app no las sube a ningún servidor. Ten en cuenta que las copias de seguridad del iPhone (iCloud o Finder) incluyen los datos de las apps.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            Button("Eliminar todo el historial de fotos", role: .destructive) { confirmDeleteAll = true }
                .font(.footnote.weight(.semibold))
                .disabled(photos.isEmpty)
        }
        .card()
    }

    private func save(_ item: PhotosPickerItem, view: PhotoView) async {
        isSaving = true
        defer {
            isSaving = false
            pickerItem = nil
            targetView = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "No se pudo cargar la imagen."
                return
            }
            try PhotoStorage.save(imageData: data, year: current.year, month: current.month, view: view, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// La foto más reciente de esa vista en un mes anterior: sirve de guía para repetir la postura.
    private func previousPhoto(_ view: PhotoView) -> ProgressPhoto? {
        photos.first { $0.view == view && !($0.year == current.year && $0.month == current.month) }
    }

    private func saveData(_ data: Data, view: PhotoView) {
        do {
            try PhotoStorage.save(imageData: data, year: current.year, month: current.month, view: view, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ photo: ProgressPhoto?) {
        guard let photo else { return }
        do { try PhotoStorage.delete(photo, in: context) } catch { errorMessage = error.localizedDescription }
    }
}

struct MonthPhotosView: View {
    let year: Int
    let month: Int

    @Environment(\.modelContext) private var context
    @Query private var photos: [ProgressPhoto]
    @State private var viewing: ProgressPhoto?
    @State private var pendingDelete: ProgressPhoto?

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
        _photos = Query(filter: #Predicate<ProgressPhoto> { $0.year == year && $0.month == month })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(PhotoView.allCases) { view in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(view.label).font(.headline)
                        if let photo = photos.first(where: { $0.view == view }), let image = PhotoStorage.image(photo.fileName, maxPixel: 1200) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { viewing = photo }
                            Button("Eliminar esta foto", role: .destructive) { pendingDelete = photo }
                                .font(.footnote)
                        } else {
                            Text("Sin foto").font(.footnote).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .card()
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(DateUtils.monthTitle(year: year, month: month))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { PhotoViewer(photo: $0) }
        .confirmationDialog("¿Eliminar esta foto?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let p = pendingDelete { try? PhotoStorage.delete(p, in: context) }
                pendingDelete = nil
            }
        }
    }
}

struct PhotoViewer: View {
    let photo: ProgressPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.background.ignoresSafeArea()
            if let image = PhotoStorage.loadImage(photo.fileName) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(Theme.textPrimary.opacity(0.8))
            }
            .padding()
        }
    }
}

/// Antes / después de dos meses, por vista: deslizador sobre la foto (por defecto) o lado a lado.
struct PhotoCompareView: View {
    @Query private var photos: [ProgressPhoto]
    @State private var view: PhotoView = .front
    @State private var leftKey = ""
    @State private var rightKey = ""
    @State private var overlay = true
    @State private var split: CGFloat = 0.5

    private var months: [(key: String, year: Int, month: Int)] {
        var seen = Set<String>()
        return photos
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
            .compactMap { p in
                let key = String(format: "%04d-%02d", p.year, p.month)
                return seen.insert(key).inserted ? (key, p.year, p.month) : nil
            }
    }

    private func photo(for key: String) -> ProgressPhoto? {
        photos.first { String(format: "%04d-%02d", $0.year, $0.month) == key && $0.view == view }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Vista", selection: $view) {
                    ForEach(PhotoView.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    monthPicker("Antes", selection: $leftKey)
                    monthPicker("Después", selection: $rightKey)
                }

                Picker("Modo", selection: $overlay) {
                    Text("Deslizador").tag(true)
                    Text("Lado a lado").tag(false)
                }
                .pickerStyle(.segmented)

                if overlay {
                    overlayView
                } else {
                    HStack(spacing: 8) {
                        image(for: leftKey)
                        image(for: rightKey)
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Antes / después")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if leftKey.isEmpty { leftKey = months.last?.key ?? "" }
            if rightKey.isEmpty { rightKey = months.first?.key ?? "" }
        }
    }

    private func monthPicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Theme.lime)
            Picker(title, selection: selection) {
                ForEach(months, id: \.key) { m in
                    Text(DateUtils.monthTitle(year: m.year, month: m.month)).tag(m.key)
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    @ViewBuilder
    private func image(for key: String) -> some View {
        if let p = photo(for: key), let img = PhotoStorage.image(p.fileName, maxPixel: 1200) {
            Image(uiImage: img).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .frame(maxWidth: .infinity, minHeight: 220)
                .overlay(Text("Sin foto").font(.caption).foregroundStyle(Theme.textTertiary))
        }
    }

    /// «Antes» a la izquierda del deslizador y «Después» a la derecha. Arrastra sobre la foto para mover la línea.
    @ViewBuilder
    private var overlayView: some View {
        if let before = photo(for: leftKey).flatMap({ PhotoStorage.image($0.fileName, maxPixel: 1600) }),
           let after = photo(for: rightKey).flatMap({ PhotoStorage.image($0.fileName, maxPixel: 1600) }) {
            VStack(spacing: 10) {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        Image(uiImage: after).resizable().scaledToFit()
                            .frame(width: width, height: geo.size.height)
                        Image(uiImage: before).resizable().scaledToFit()
                            .frame(width: width, height: geo.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: width * split) }
                        Rectangle().fill(Theme.lime).frame(width: 3)
                            .offset(x: width * split - 1.5)
                        Circle().fill(Theme.lime).frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.heavy)).foregroundStyle(Theme.onLime))
                            .offset(x: width * split - 17)
                    }
                    .overlay(alignment: .topLeading) { tag("ANTES").padding(8) }
                    .overlay(alignment: .topTrailing) { tag("DESPUÉS").padding(8) }
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                        split = min(max(value.location.x / max(width, 1), 0), 1)
                    })
                }
                .frame(height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Slider(value: $split, in: 0...1).tint(Theme.lime)
                    .accessibilityLabel("Deslizador antes y después")
                Text("Arrastra sobre la foto: a la izquierda, «Antes»; a la derecha, «Después».")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        } else {
            Text("Elige dos meses que tengan foto de \(view.label.lowercased()).")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.heavy)).tracking(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .foregroundStyle(Theme.lime)
    }
}
