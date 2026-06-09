import UIKit

/// Carries OCR scan results and captured image to the meal/expense form for pre-filling.
struct ScanPrefillData {
    let date: Date?
    let amount: String?
    let merchantName: String?
    let capturedImage: UIImage

    enum MealSlot: String, CaseIterable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
    }

    let mealSlot: MealSlot?
}
