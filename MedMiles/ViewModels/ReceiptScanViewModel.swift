import SwiftUI
import Combine

enum ReceiptScanState: Equatable {
    case idle
    case scanning
    case review
}

@MainActor
final class ReceiptScanViewModel: ObservableObject {
    @Published var state: ReceiptScanState = .idle
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?

    // OCR results (used to build ScanPrefillData for forms)
    @Published var merchantName = ""
    @Published var amount = ""
    @Published var date = Date()
    @Published var category: ReceiptCategory = .expense

    // MARK: - Process Image

    func processImage(_ image: UIImage) {
        capturedImage = image
        state = .scanning
        errorMessage = nil

        Task {
            do {
                let result = try await ReceiptScannerService.shared.scan(image: image)

                merchantName = result.merchantName ?? ""
                amount = result.totalAmount ?? ""
                if let scannedDate = result.date {
                    date = scannedDate
                }
                category = result.detectedCategory

                state = .review
            } catch {
                errorMessage = "Could not read receipt. Please fill in the details manually."
                state = .review
            }
        }
    }

    // MARK: - Reset

    func reset() {
        state = .idle
        capturedImage = nil
        errorMessage = nil
        merchantName = ""
        amount = ""
        date = Date()
        category = .expense
    }
}
