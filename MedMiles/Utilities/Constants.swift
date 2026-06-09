import Foundation

enum Constants {
    // MARK: - Supabase
    // swiftlint:disable:next force_unwrapping
    static let supabaseURL: URL = {
        guard let url = URL(string: "https://vvtvydidosiipsdvihgq.supabase.co") else {
            fatalError("Invalid Supabase URL — this is a compile-time constant and should never fail")
        }
        return url
    }()
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ2dHZ5ZGlkb3NpaXBzZHZpaGdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NTk5ODksImV4cCI6MjA4OTUzNTk4OX0.Zz40VZR8RRIgFwTQPsnWJIBXEMOfPGZRYky_Xg1v9HU"

    // MARK: - Google Maps
    static let googleMapsAPIKey = "AIzaSyCOHPt_iZnmsqau9CXpWJSE3-nMX0fHiMY"

    // MARK: - Tax
    static let defaultTaxSetAsidePct: Decimal = 30.0

    // MARK: - Brand Colors
    enum Colors {
        static let graphite = "GraphiteColor"       // #363638
        static let mintTeal = "MintTealColor"       // #00B5A5
        static let background = "BackgroundSurface" // #F7F8F9
        static let errorRed = "ErrorRed"            // #E24B4A
        static let warningAmber = "WarningAmber"    // #EF9F27
        static let successGreen = "SuccessGreen"    // #0B8A6E
    }
}
