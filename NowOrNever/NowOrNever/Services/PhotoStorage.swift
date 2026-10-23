import Foundation
import ImageIO
import SwiftData
import UIKit

/// Guarda las fotos de progreso SOLO en el contenedor privado de la app (Application Support),
/// con protección de datos completa. Nunca se suben a ningún servidor.
enum PhotoStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func loadImage(_ fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        return UIImage(contentsOfFile: url(for: fileName).path)
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    /// Versión reducida (lado mayor `maxPixel`) y guardada en memoria: las pantallas no vuelven a leer
    /// y descomprimir la foto completa del disco en cada redibujado (ni en cada movimiento del deslizador).
    /// Cada foto nueva tiene otro nombre de archivo, así que nunca se muestra una versión antigua.
    static func image(_ fileName: String, maxPixel: Int) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        let key = "\(fileName)@\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url(for: fileName) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }

    /// Normaliza a JPEG (máx. 2048 px) y guarda. Si ya hay foto para ese mes y vista, la reemplaza
    /// (solo cuando el usuario lo ha confirmado en la interfaz).
    @MainActor
    static func save(imageData: Data, year: Int, month: Int, view: PhotoView, in context: ModelContext) throws {
        guard let image = UIImage(data: imageData) else { throw PhotoError.invalidImage }
        let resized = downscale(image, maxDimension: 2048)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { throw PhotoError.invalidImage }

        let fileName = String(format: "%04d-%02d", year, month) + "-\(view.rawValue)-\(UUID().uuidString.prefix(8)).jpg"
        try jpeg.write(to: url(for: fileName), options: [.atomic, .completeFileProtection])

        let key = ProgressPhoto.makeKey(year: year, month: month, view: view)
        var descriptor = FetchDescriptor<ProgressPhoto>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            let oldFile = existing.fileName
            existing.fileName = fileName
            existing.updatedAt = Date()
            try context.save()
            try? FileManager.default.removeItem(at: url(for: oldFile))
        } else {
            context.insert(ProgressPhoto(year: year, month: month, view: view, fileName: fileName))
            try context.save()
        }
    }

    @MainActor
    static func delete(_ photo: ProgressPhoto, in context: ModelContext) throws {
        let file = photo.fileName
        context.delete(photo)
        try context.save()
        try? FileManager.default.removeItem(at: url(for: file))
    }

    /// Elimina TODAS las fotos y su historial.
    @MainActor
    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: ProgressPhoto.self)
        try context.save()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    enum PhotoError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "No se pudo leer la imagen seleccionada." }
    }
}
