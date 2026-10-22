import Foundation

public enum DisplayGroup: String, Codable, CaseIterable, Sendable {
    case open
    case closed
    case unmanaged

    public var title: String {
        switch self {
        case .open: return "开盖显示"
        case .closed: return "合盖显示"
        case .unmanaged: return "交给系统"
        }
    }

    public var help: String {
        switch self {
        case .open: return "MacBook 开盖时启用这块屏幕，合盖时停用"
        case .closed: return "MacBook 合盖时启用这块屏幕，开盖时停用"
        case .unmanaged: return "LidSwitch 不控制这块屏幕，由 macOS 自行管理"
        }
    }

    public func matches(_ lid: LidState) -> Bool {
        (self == .open && lid == .open) || (self == .closed && lid == .closed)
    }
}
