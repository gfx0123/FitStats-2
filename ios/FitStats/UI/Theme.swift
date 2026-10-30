import SwiftUI

enum Theme {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    /// The tint over a card's frosted glass (Glass in Components.swift); widgets draw it plain.
    static let card = Color(red: 0.02, green: 0.07, blue: 0.08).opacity(0.30)
    static let cardBorder = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.12)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)

    static let recoveryGreen = Color(red: 0.18, green: 0.90, blue: 0.62)
    static let recoveryYellow = Color(red: 1.00, green: 0.82, blue: 0.35)
    static let recoveryRed = Color(red: 1.00, green: 0.36, blue: 0.38)
    static let strain = Color(red: 0.30, green: 0.55, blue: 1.00)
    static let strainEnd = Color(red: 0.50, green: 0.38, blue: 1.00)
    static let sleep = Color(red: 0.61, green: 0.48, blue: 1.00)
    static let stress = Color(red: 0.24, green: 0.84, blue: 0.77)
    static let heart = Color(red: 1.00, green: 0.38, blue: 0.47)
    static let body = Color(red: 1.00, green: 0.66, blue: 0.30)

    static let stageAwake = Color(red: 1.00, green: 0.55, blue: 0.40)
    static let stageRem = Color(red: 0.36, green: 0.80, blue: 1.00)
    static let stageLight = Color(red: 0.47, green: 0.52, blue: 1.00)
    static let stageDeep = Color(red: 0.42, green: 0.26, blue: 0.90)
    static let stageRestless = Color(red: 1.00, green: 0.78, blue: 0.42)

    static func recoveryColor(_ v: Double?) -> Color {
        guard let v else { return tertiary }
        if v >= 67 { return recoveryGreen }
        if v >= 34 { return recoveryYellow }
        return recoveryRed
    }

    static func stressColor(_ v: Double?) -> Color {
        guard let v else { return tertiary }
        if v < 25 { return stress }
        if v < 50 { return recoveryYellow }
        if v < 75 { return body }
        return recoveryRed
    }

    static func stressLabel(_ v: Double?) -> String {
        guard let v else { return "No data" }
        if v < 25 { return "Low" }
        if v < 50 { return "Moderate" }
        if v < 75 { return "High" }
        return "Very high"
    }

    static func recoveryLabel(_ v: Double?) -> String {
        guard let v else { return "No data" }
        if v >= 67 { return "Ready to perform" }
        if v >= 34 { return "Maintain" }
        return "Take it easy"
    }

    static func stageColor(_ code: Int) -> Color {
        switch code {
        case 0: return stageAwake
        case 3: return stageRem
        case 2: return stageDeep
        default: return stageLight
        }
    }

    static func stageName(_ code: Int) -> String {
        switch code {
        case 0: return "Awake"
        case 1: return "Light"
        case 2: return "Deep"
        case 3: return "REM"
        case 4: return "Asleep"
        case 5: return "Restless"
        default: return "Unknown"
        }
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
