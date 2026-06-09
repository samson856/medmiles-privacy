import Foundation

struct MonthGroup<T>: Identifiable {
    let id: String  // "2026-03"
    let label: String  // "March 2026"
    let items: [T]
}

enum MonthGrouping {
    /// Groups items by month from a date string in "yyyy-MM-dd" format.
    /// Returns groups sorted by most recent month first.
    static func group<T>(_ items: [T], by dateKeyPath: KeyPath<T, String>) -> [MonthGroup<T>] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMMM yyyy"

        let monthKeyFormatter = DateFormatter()
        monthKeyFormatter.dateFormat = "yyyy-MM"

        var grouped: [String: (label: String, items: [T])] = [:]

        for item in items {
            let dateStr = item[keyPath: dateKeyPath]
            guard let date = formatter.date(from: dateStr) else { continue }
            let key = monthKeyFormatter.string(from: date)
            let label = displayFormatter.string(from: date)

            if grouped[key] != nil {
                grouped[key]?.items.append(item)
            } else {
                grouped[key] = (label: label, items: [item])
            }
        }

        return grouped
            .map { MonthGroup(id: $0.key, label: $0.value.label, items: $0.value.items) }
            .sorted { $0.id > $1.id }  // Most recent first
    }
}
