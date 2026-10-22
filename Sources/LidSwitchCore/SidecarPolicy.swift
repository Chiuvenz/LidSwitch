import Foundation

public enum SidecarIdentity {
    public static let displayVendor: UInt32 = 0x6161706c // "aapl"
    public static let displayModel: UInt32 = 0x69506164 // "iPad"

    /// On the verified Sidecar implementation the virtual display serial is
    /// the first 32 bits of the device UUID. Use only for migrating a legacy
    /// display selection; future connections are tracked by the full UUID.
    public static func displaySerial(for identifier: String) -> UInt32? {
        guard UUID(uuidString: identifier) != nil else { return nil }
        return UInt32(identifier.prefix(8), radix: 16)
    }
}

public enum SidecarGoal: Equatable, Sendable {
    case connect
    case disconnect
}

public struct SidecarRetryBudget: Sendable {
    public private(set) var attempts = 0
    public private(set) var context: String?
    public let limit: Int

    public init(limit: Int = 3) { self.limit = limit }

    public mutating func update(context: String) {
        guard self.context != context else { return }
        self.context = context
        attempts = 0
    }

    public mutating func beginAttempt() -> Bool {
        guard attempts < limit else { return false }
        attempts += 1
        return true
    }
}

public struct SidecarPolicy: Sendable {
    public init() {}

    public func goal(
        lid: LidState, builtInActive: Bool, externalActive: Bool,
        group: DisplayGroup = .closed
    ) -> SidecarGoal? {
        guard group != .unmanaged else { return nil }
        switch lid {
        case .open:
            return builtInActive ? (group == .open ? .connect : .disconnect) : nil
        case .closed:
            // Do not try to keep a headless/sleeping Mac awake by reconnecting
            // Sidecar. A usable display must already exist before connecting.
            return externalActive ? (group == .closed ? .connect : .disconnect) : nil
        case .unknown:
            return nil
        }
    }
}
