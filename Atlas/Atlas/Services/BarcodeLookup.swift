import Foundation
import Observation

/// Consulta un código de barras en Open Food Facts.
///
/// Es una base de datos abierta y gratuita, sin clave. Los datos los suben voluntarios, así que
/// la app enseña siempre lo que ha encontrado y deja corregirlo antes de apuntarlo: nunca da
/// por buenas unas calorías sin que las veas. Si el producto no está, no se inventa nada.
@MainActor
@Observable
final class BarcodeLookup {
    enum Outcome: Equatable {
        case found(OpenFoodFacts.Product)
        case failed(OpenFoodFacts.LookupError)
    }

    var isWorking = false

    @ObservationIgnored private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Versión de la app, para identificarse ante Open Food Facts como piden en su API.
    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    func lookup(_ rawBarcode: String) async -> Outcome {
        let barcode = rawBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OpenFoodFacts.isPlausible(barcode) else { return .failed(.badBarcode(barcode)) }
        guard let url = OpenFoodFacts.url(for: barcode) else { return .failed(.badBarcode(barcode)) }

        isWorking = true
        defer { isWorking = false }

        var request = URLRequest(url: url)
        request.setValue(OpenFoodFacts.userAgent(version: Self.appVersion), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .failed(.notFound(barcode))
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed(.network("el servidor ha respondido \(http.statusCode)"))
            }
            return .found(try OpenFoodFacts.parse(data, barcode: barcode))
        } catch let error as OpenFoodFacts.LookupError {
            return .failed(error)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }
}
