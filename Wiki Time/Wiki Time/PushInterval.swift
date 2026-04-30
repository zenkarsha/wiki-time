import Foundation

enum PushInterval: String, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case fifteenMinutes
    case thirtyMinutes
    case fortyFiveMinutes
    case oneHour
    case twoHours
    case threeHours
    case fourHours
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMinute:
            "1 分鐘"
        case .fiveMinutes:
            "5 分鐘"
        case .tenMinutes:
            "10 分鐘"
        case .fifteenMinutes:
            "15 分鐘"
        case .thirtyMinutes:
            "30 分鐘"
        case .fortyFiveMinutes:
            "45 分鐘"
        case .oneHour:
            "1 小時"
        case .twoHours:
            "2 小時"
        case .threeHours:
            "3 小時"
        case .fourHours:
            "4 小時"
        case .custom:
            "自訂"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute:
            60
        case .fiveMinutes:
            5 * 60
        case .tenMinutes:
            10 * 60
        case .fifteenMinutes:
            15 * 60
        case .thirtyMinutes:
            30 * 60
        case .fortyFiveMinutes:
            45 * 60
        case .oneHour:
            60 * 60
        case .twoHours:
            2 * 60 * 60
        case .threeHours:
            3 * 60 * 60
        case .fourHours:
            4 * 60 * 60
        case .custom:
            0
        }
    }
}
