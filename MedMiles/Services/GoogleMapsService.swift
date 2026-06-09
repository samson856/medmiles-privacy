import Foundation

struct DistanceMatrixResponse: Codable {
    let rows: [Row]
    let status: String

    struct Row: Codable {
        let elements: [Element]
    }

    struct Element: Codable {
        let distance: ValueText?
        let duration: ValueText?
        let status: String
    }

    struct ValueText: Codable {
        let text: String
        let value: Int // meters for distance, seconds for duration
    }
}

final class GoogleMapsService {
    static let shared = GoogleMapsService()
    private init() {}

    /// Calculate driving distance between two addresses.
    /// Returns distance in miles, or nil if the lookup fails.
    func calculateDistance(from origin: String, to destination: String) async -> Double? {
        let apiKey = Constants.googleMapsAPIKey
        guard !origin.isEmpty, !destination.isEmpty else { return nil }

        let encodedOrigin = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedDest = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let urlString = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=\(encodedOrigin)&destinations=\(encodedDest)&units=imperial&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(DistanceMatrixResponse.self, from: data)

            guard response.status == "OK",
                  let element = response.rows.first?.elements.first,
                  element.status == "OK",
                  let distance = element.distance else {
                return nil
            }

            // Convert meters to miles
            let miles = Double(distance.value) / 1609.34
            return miles
        } catch {
            return nil
        }
    }
}
