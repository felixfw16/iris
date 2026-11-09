import Foundation

enum SessionError: LocalizedError {
    case invalid(String)
    case unavailable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unavailable(let message): return message
        case .cancelled: return "Permintaan dibatalkan."
        }
    }

    var code: String {
        switch self {
        case .invalid: return "operation"
        case .unavailable: return "unavailable"
        case .cancelled: return "cancelled"
        }
    }
}
