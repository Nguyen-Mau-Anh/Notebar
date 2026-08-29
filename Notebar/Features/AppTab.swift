import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case notes
    case tasks
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:    return "Notes"
        case .tasks:    return "Tasks"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .notes:    return "doc.text"
        case .tasks:    return "checklist"
        case .settings: return "gearshape"
        }
    }
}
