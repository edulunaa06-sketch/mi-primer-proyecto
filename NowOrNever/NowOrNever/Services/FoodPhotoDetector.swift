import UIKit
import Vision

/// Reconoce alimentos en una foto con el clasificador de imágenes del propio iPhone (Vision).
/// Gratis, sin internet y sin enviar la foto a ningún sitio.
enum FoodPhotoDetector {
    static func labels(in jpeg: Data) async -> [FoodVision.Label] {
        guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).map { FoodVision.Label(identifier: $0.identifier, confidence: Double($0.confidence)) }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
