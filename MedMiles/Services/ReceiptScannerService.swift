import Vision
import UIKit
import ImageIO

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
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

/// Result of scanning a receipt with OCR.
struct ScannedReceipt {
    var merchantName: String?
    var totalAmount: String?
    var date: Date?
    var detectedCategory: ReceiptCategory
    var rawText: String
}

enum ReceiptCategory: String, CaseIterable {
    case meal = "Meal"
    case expense = "Expense"
}

/// Uses Apple Vision framework for on-device OCR to extract receipt data.
final class ReceiptScannerService {
    static let shared = ReceiptScannerService()
    private init() {}

    // MARK: - Food / restaurant keywords for category detection
    private static let mealKeywords: Set<String> = [
        "restaurant", "cafe", "coffee", "diner", "grill", "bistro", "pizz",
        "burger", "taco", "sushi", "bar", "pub", "brew", "bakery",
        "breakfast", "lunch", "dinner", "appetizer", "entree", "dessert",
        "tip", "gratuity", "server", "waiter", "waitress",
        "subtotal", "food", "beverage", "drink", "doordash", "ubereats",
        "grubhub", "starbucks", "mcdonald", "chick-fil-a", "chipotle",
        "panera", "subway", "wendy", "dunkin",
    ]

    // MARK: - Scan

    func scan(image: UIImage) async throws -> ScannedReceipt {
        guard let cgImage = image.cgImage else {
            return ScannedReceipt(detectedCategory: .expense, rawText: "")
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let recognizedText = try await performOCR(on: cgImage, orientation: orientation)
        let fullText = recognizedText.joined(separator: "\n")
        let lowerText = fullText.lowercased()

        let amount = parseTotal(from: recognizedText)
        let date = parseDate(from: recognizedText)
        let merchant = parseMerchant(from: recognizedText)
        let category = detectCategory(from: lowerText)

        return ScannedReceipt(
            merchantName: merchant,
            totalAmount: amount,
            date: date,
            detectedCategory: category,
            rawText: fullText
        )
    }

    // MARK: - OCR

    private func performOCR(on cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Parse Total

    private func parseTotal(from lines: [String]) -> String? {
        // Strategy: look for lines with "total" keyword and a dollar amount
        // Prefer "total" over "subtotal" — pick the last/largest "total" match
        let totalPattern = /(?:total|amount\s*due|balance\s*due|grand\s*total)\s*[:\s]*\$?\s*(\d+[.,]\d{2})/
        let genericDollarPattern = /\$\s*(\d+[.,]\d{2})/

        var bestTotal: (value: Double, text: String)?

        for line in lines {
            let lower = line.lowercased()
            // Skip subtotal lines
            if lower.contains("subtotal") || lower.contains("sub total") { continue }

            if let match = lower.firstMatch(of: totalPattern) {
                let amountStr = String(match.1).replacingOccurrences(of: ",", with: "")
                if let val = Double(amountStr) {
                    if val > (bestTotal?.value ?? -1) {
                        bestTotal = (val, amountStr)
                    }
                }
            }
        }

        if let best = bestTotal {
            return best.text
        }

        // Fallback: find the largest dollar amount on any line
        var largest: (value: Double, text: String)?
        for line in lines {
            let lower = line.lowercased()
            // Skip lines that look like tax, tip, or change
            if lower.contains("tax") || lower.contains("change") { continue }

            for match in line.matches(of: genericDollarPattern) {
                let amountStr = String(match.1).replacingOccurrences(of: ",", with: "")
                if let val = Double(amountStr) {
                    if val > (largest?.value ?? -1) {
                        largest = (val, amountStr)
                    }
                }
            }
        }

        return largest?.text
    }

    // MARK: - Parse Date

    private func parseDate(from lines: [String]) -> Date? {
        // Allow dates up to end of today (+1 day grace for timezone differences)
        // and back two years (covers current + prior tax year receipts).
        let calendar = Calendar.current
        guard let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: Date()),
              let graceEnd = calendar.date(byAdding: .day, value: 1, to: endOfToday),
              let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: Date()) else {
            return nil
        }
        func inWindow(_ d: Date) -> Bool { d >= twoYearsAgo && d <= graceEnd }

        // ── Primary: Apple's NSDataDetector ──
        // This is the same engine iOS uses to make dates tappable in Mail/Messages.
        // It recognizes far more real-world receipt date formats (with/without
        // years, times, ALL-CAPS months, ordinals, etc.) than hand-rolled regex.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            // Pass 1: prefer a date sitting on a line that names it (most reliable).
            // Pass 2: any date anywhere in the receipt, in reading order.
            let keywordLines = lines.filter { line in
                let l = line.lowercased()
                return l.contains("date") || l.contains("sold") || l.contains("trans")
                    || l.contains("order") || l.contains("invoice") || l.contains("purchased")
            }
            for group in [keywordLines, lines] {
                for line in group {
                    let nsLine = line as NSString
                    let range = NSRange(location: 0, length: nsLine.length)
                    for match in detector.matches(in: line, options: [], range: range) {
                        guard let d = match.date, inWindow(d) else { continue }
                        // Reject time-only matches (e.g. "2:32 PM") that resolve to
                        // today — require the matched text to actually look like a date.
                        let matched = nsLine.substring(with: match.range)
                        let looksLikeDate = matched.contains("/") || matched.contains("-")
                            || matched.contains(".")
                            || matched.range(of: "[A-Za-z]{3,}", options: .regularExpression) != nil
                        if looksLikeDate {
                            return d
                        }
                    }
                }
            }
        }

        // ── Fallback: explicit regex + DateFormatter passes ──
        let dateFormats = [
            "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
            "MM-dd-yyyy", "M-d-yyyy", "MM-dd-yy", "M-d-yy",
            "MM.dd.yyyy", "M.d.yyyy", "MM.dd.yy", "M.d.yy",
            "MMM dd, yyyy", "MMMM dd, yyyy", "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM dd yyyy", "MMMM dd yyyy", "MMM d yyyy",
            "MMMM d yyyy",
            "yyyy-MM-dd",
        ]

        // Match numeric dates like 04/04/2026, 4/4/26, 04-04-2026, 04.04.2026
        // Allow optional spaces around separators (OCR artifact)
        let datePattern = /\d{1,2}\s?[\/\-\.]\s?\d{1,2}\s?[\/\-\.]\s?\d{2,4}/

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for line in lines {
            if let match = line.firstMatch(of: datePattern) {
                // Strip any spaces OCR may add around separators (e.g. "04 / 04 / 2026")
                let dateStr = String(match.0).replacingOccurrences(of: " ", with: "")
                if let parsed = tryParse(dateStr, formats: dateFormats, formatter: formatter) {
                    if parsed >= twoYearsAgo && parsed <= endOfToday {
                        return parsed
                    }
                }
            }
        }

        // Try text-based dates like "Jan 15, 2026", "January 15, 2026",
        // "JAN 15, 2026", "JANUARY 15, 2026" (OCR often returns ALL CAPS)
        let textDatePattern = /[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}/
        for line in lines {
            if let match = line.firstMatch(of: textDatePattern) {
                // Normalize OCR case to title case for DateFormatter
                let raw = String(match.0)
                let dateStr = raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
                if let parsed = tryParse(dateStr, formats: dateFormats, formatter: formatter) {
                    if parsed >= twoYearsAgo && parsed <= endOfToday {
                        return parsed
                    }
                }
            }
        }

        // Try looser patterns: dates embedded in longer lines (e.g. "Date: 04/04/2026")
        let embeddedPattern = /(?:date|dated|dt)[:\s]+(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})/
        for line in lines {
            let lower = line.lowercased()
            if let match = lower.firstMatch(of: embeddedPattern) {
                let dateStr = String(match.1)
                if let parsed = tryParse(dateStr, formats: dateFormats, formatter: formatter) {
                    if parsed >= twoYearsAgo && parsed <= endOfToday {
                        return parsed
                    }
                }
            }
        }

        return nil
    }

    private func tryParse(_ dateStr: String, formats: [String], formatter: DateFormatter) -> Date? {
        for format in formats {
            formatter.dateFormat = format

            // For 2-digit year formats, set the century pivot so "26" → 2026
            if format.hasSuffix("yy") && !format.hasSuffix("yyyy") {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = formatter.timeZone
                // Pivot: 2-digit years are interpreted as 2000–2099
                let pivotYear = 2000
                let pivotComponents = DateComponents(year: pivotYear)
                if let pivotDate = cal.date(from: pivotComponents) {
                    formatter.twoDigitStartDate = pivotDate
                }
            }

            if let date = formatter.date(from: dateStr) {
                return date
            }
        }
        return nil
    }

    // MARK: - Parse Merchant

    private func parseMerchant(from lines: [String]) -> String? {
        // Heuristic: first non-empty, non-numeric line that isn't a date or address
        let skipPatterns: [Regex<Substring>] = [
            /^\d+$/, // pure numbers
            /^\d{1,2}[\/\-]/, // dates
            /^\d+\s+(?:st|nd|rd|th|ave|blvd|dr|ln|ct)\b/,  // addresses
        ]

        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count >= 3 else { continue }

            let lower = trimmed.lowercased()
            var skip = false
            for pattern in skipPatterns {
                if lower.firstMatch(of: pattern) != nil {
                    skip = true
                    break
                }
            }
            if skip { continue }

            // Skip if it looks like a phone number
            if trimmed.filter({ $0.isNumber }).count > 7 { continue }

            return trimmed
        }
        return nil
    }

    // MARK: - Detect Category

    private func detectCategory(from lowerText: String) -> ReceiptCategory {
        var mealScore = 0
        for keyword in Self.mealKeywords {
            if lowerText.contains(keyword) { mealScore += 1 }
        }
        return mealScore >= 2 ? .meal : .expense
    }
}
