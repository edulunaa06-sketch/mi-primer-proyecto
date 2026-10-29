import AVFoundation
import SwiftUI
import UIKit

/// Cámara para las fotos de progreso: delantera o trasera, temporizador (para hacerte la de espalda tú solo)
/// y, si existe, la foto del mes anterior superpuesta en transparencia para repetir la misma postura.
struct CameraCaptureView: View {
    let view: PhotoView
    let guide: UIImage?
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var timer = 10
    @State private var countdown: Int?
    @State private var showGuide = true
    @State private var guideOpacity = 0.35
    @State private var captured: Data?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let captured, let image = UIImage(data: captured) {
                review(image)
            } else {
                live
            }
        }
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var live: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Text(view.label).font(.headline)
                Spacer()
                Button { camera.switchCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title3)
                }
                .accessibilityLabel("Cambiar de cámara")
                .disabled(countdown != nil)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding()

            ZStack {
                switch camera.state {
                case .denied:
                    message("Now or Never no tiene permiso para usar la cámara. Actívalo en Ajustes › Now or Never › Cámara, o elige la foto de la galería.")
                case .unavailable:
                    message("Este dispositivo no tiene cámara disponible (por ejemplo, el simulador). Elige la foto de la galería.")
                case .starting, .running:
                    CameraPreview(session: camera.session, mirrored: camera.isFront)
                    if showGuide, let guide {
                        Image(uiImage: guide).resizable().scaledToFit().opacity(guideOpacity).allowsHitTesting(false)
                    }
                    if let countdown {
                        Text("\(countdown)")
                            .font(.system(size: 120, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.lime)
                            .shadow(radius: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            VStack(spacing: 14) {
                if guide != nil && showGuide {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(Theme.textPrimary)
                        Slider(value: $guideOpacity, in: 0.1...0.7).tint(Theme.lime)
                            .accessibilityLabel("Transparencia de la foto anterior")
                        Text(NumberFormat.percent(guideOpacity)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                            .frame(width: 40)
                    }
                    .padding(.horizontal, 24)
                }
                HStack(spacing: 8) {
                    ForEach([0, 3, 10], id: \.self) { s in
                        Button(s == 0 ? "Sin temporizador" : "\(s) s") { timer = s }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(timer == s ? Theme.lime : Theme.cardRaised, in: Capsule())
                            .foregroundStyle(timer == s ? Theme.onLime : Theme.textPrimary)
                    }
                    if guide != nil {
                        Button { showGuide.toggle() } label: {
                            Image(systemName: showGuide ? "person.fill.viewfinder" : "person.crop.rectangle")
                        }
                        .padding(8)
                        .background(showGuide ? Theme.lime : Theme.cardRaised, in: Circle())
                        .foregroundStyle(showGuide ? Theme.onLime : Theme.textPrimary)
                        .accessibilityLabel(showGuide ? "Ocultar la foto del mes anterior" : "Mostrar la foto del mes anterior")
                    }
                }
                .disabled(countdown != nil)

                Button(action: shoot) {
                    ZStack {
                        Circle().stroke(Theme.textPrimary, lineWidth: 4).frame(width: 74, height: 74)
                        Circle().fill(countdown == nil ? Theme.lime : Theme.danger).frame(width: 60, height: 60)
                    }
                }
                .accessibilityLabel(countdown == nil ? "Hacer foto" : "Cancelar temporizador")
                .disabled(camera.state != .running)

                Text(guide != nil && showGuide ? "Colócate como en la foto del mes anterior." : "Misma luz, distancia y postura cada mes.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 16)
        }
    }

    private func review(_ image: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                Button("Repetir") { captured = nil }
                    .buttonStyle(LimeButtonStyle(filled: false))
                Button("Usar foto") {
                    if let captured { onCapture(captured) }
                    dismiss()
                }
                .buttonStyle(LimeButtonStyle())
            }
            .padding()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).multilineTextAlignment(.center).foregroundStyle(Theme.textPrimary).padding(32)
    }

    private func shoot() {
        if countdown != nil { countdown = nil; return }
        guard timer > 0 else { capture(); return }
        countdown = timer
        Task { @MainActor in
            while let c = countdown, c > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard countdown != nil else { return }
                countdown = c - 1
            }
            guard countdown == 0 else { return }
            countdown = nil
            capture()
        }
    }

    private func capture() {
        Task { @MainActor in captured = await camera.capture() }
    }
}

/// Sesión de AVFoundation: arranque, cambio de cámara y disparo.
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    enum State { case starting, running, denied, unavailable }

    var state: State = .starting
    var isFront = false
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "Atlas.camera")
    @ObservationIgnored private var continuation: CheckedContinuation<Data?, Never>?

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
        guard configure(front: isFront) else { state = .unavailable; return }
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

    @MainActor
    func switchCamera() {
        if configure(front: !isFront) { isFront.toggle() }
    }

    private func configure(front: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = front }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
        return true
    }

    @MainActor
    func capture() async -> Data? {
        guard state == .running, continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        DispatchQueue.main.async {
            self.continuation?.resume(returning: data)
            self.continuation = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
