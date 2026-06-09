import Foundation
import UIKit

/// Saves receipt and credential images to the app's local Documents directory.
/// Files persist on-device only — not synced to any cloud service.
/// Receipts are isolated per user ID to prevent cross-user data leakage.
final class LocalStorageService {
    static let shared = LocalStorageService()
    private init() {}

    /// The currently active user ID. Must be set before performing any receipt operations.
    private var currentUserId: UUID?

    /// Set the active user whose receipts should be accessed.
    /// Call this on sign-in and session restore.
    func setCurrentUser(userId: UUID) {
        currentUserId = userId
    }

    /// Clear the active user on sign-out so no stale directory is referenced.
    func clearCurrentUser() {
        currentUserId = nil
    }

    /// User-scoped receipts directory: Documents/receipts/{userId}/
    private var receiptsDirectory: URL {
        guard let userId = currentUserId else {
            return FileManager.default.temporaryDirectory
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return FileManager.default.temporaryDirectory
        }
        let dir = docs
            .appendingPathComponent("receipts", isDirectory: true)
            .appendingPathComponent(userId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Save an image as JPEG. Returns the filename on success.
    func saveReceipt(image: UIImage, for entryId: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        let filename = "\(entryId.uuidString)_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = receiptsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            return nil
        }
    }

    /// Save a raw file (PDF, etc.). Returns the filename on success.
    func saveFile(data: Data, for entryId: UUID, extension ext: String) -> String? {
        let filename = "\(entryId.uuidString)_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let url = receiptsDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            return nil
        }
    }

    /// Save a file from a URL (e.g. from Files picker). Returns the filename on success.
    func saveFileFromURL(_ sourceURL: URL, for entryId: UUID) -> String? {
        let ext = sourceURL.pathExtension.lowercased()
        guard let data = try? Data(contentsOf: sourceURL) else { return nil }
        return saveFile(data: data, for: entryId, extension: ext)
    }

    /// Returns the full file URL for a receipt filename.
    func receiptURL(filename: String) -> URL {
        receiptsDirectory.appendingPathComponent(filename)
    }

    /// Load a receipt image by filename.
    func loadReceipt(filename: String) -> UIImage? {
        let url = receiptsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete a receipt image by filename.
    func deleteReceipt(filename: String) {
        let url = receiptsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// List all receipt filenames for a given entry ID prefix.
    func receiptFilenames(for entryId: UUID) -> [String] {
        let prefix = entryId.uuidString
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: receiptsDirectory.path) else { return [] }
        return files.filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Total size of all stored receipts in bytes.
    var totalStorageUsed: Int64 {
        guard currentUserId != nil else { return 0 }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: receiptsDirectory.path) else { return 0 }
        return files.reduce(0) { total, file in
            let url = receiptsDirectory.appendingPathComponent(file)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    var formattedStorageUsed: String {
        let bytes = totalStorageUsed
        if bytes < 1_000_000 {
            return String(format: "%.0f KB", Double(bytes) / 1_000)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
    }

    /// Bundle all receipt files into organized folders for export.
    /// Returns a temporary directory URL containing subfolders (Meals/, Expenses/) with copies of all receipts.
    func bundleReceiptsForExport(mealReceipts: [(mealDate: String, agencyName: String, filenames: [String])],
                                  expenseReceipts: [(expenseDate: String, category: String, agencyName: String, filenames: [String])],
                                  taxYear: Int) -> URL? {
        let fm = FileManager.default
        let bundleDir = fm.temporaryDirectory.appendingPathComponent("MedMiles_Receipts_\(taxYear)", isDirectory: true)

        // Clean up any previous bundle
        try? fm.removeItem(at: bundleDir)

        let mealsDir = bundleDir.appendingPathComponent("Meals", isDirectory: true)
        let expensesDir = bundleDir.appendingPathComponent("Expenses", isDirectory: true)

        do {
            try fm.createDirectory(at: mealsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: expensesDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var hasMealFiles = false
        var hasExpenseFiles = false

        // Copy meal receipts
        for meal in mealReceipts {
            for (index, filename) in meal.filenames.enumerated() {
                let source = receiptsDirectory.appendingPathComponent(filename)
                guard fm.fileExists(atPath: source.path) else { continue }
                let ext = (filename as NSString).pathExtension
                let cleanAgency = meal.agencyName.replacingOccurrences(of: "/", with: "-")
                let destName = "\(meal.mealDate)_\(cleanAgency)_\(index + 1).\(ext)"
                let dest = mealsDir.appendingPathComponent(destName)
                try? fm.copyItem(at: source, to: dest)
                hasMealFiles = true
            }
        }

        // Copy expense receipts
        for expense in expenseReceipts {
            for (index, filename) in expense.filenames.enumerated() {
                let source = receiptsDirectory.appendingPathComponent(filename)
                guard fm.fileExists(atPath: source.path) else { continue }
                let ext = (filename as NSString).pathExtension
                let cleanAgency = expense.agencyName.replacingOccurrences(of: "/", with: "-")
                let cleanCategory = expense.category.replacingOccurrences(of: "/", with: "-")
                let destName = "\(expense.expenseDate)_\(cleanCategory)_\(cleanAgency)_\(index + 1).\(ext)"
                let dest = expensesDir.appendingPathComponent(destName)
                try? fm.copyItem(at: source, to: dest)
                hasExpenseFiles = true
            }
        }

        // Remove empty subfolders
        if !hasMealFiles { try? fm.removeItem(at: mealsDir) }
        if !hasExpenseFiles { try? fm.removeItem(at: expensesDir) }

        guard hasMealFiles || hasExpenseFiles else { return nil }
        return bundleDir
    }

    /// Delete all receipts for the current user (used during account deletion).
    func deleteAllReceipts() {
        guard currentUserId != nil else { return }
        let dir = receiptsDirectory
        try? FileManager.default.removeItem(at: dir)
    }

    /// Get all receipt file URLs in the receipts directory
    var allReceiptURLs: [URL] {
        guard currentUserId != nil else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: receiptsDirectory.path) else { return [] }
        return files.sorted().map { receiptsDirectory.appendingPathComponent($0) }
    }
}
