import Foundation

public struct SwitchAvailability: Equatable, Sendable {
    public let hasBuiltIn: Bool
    public let displayCount: Int
    public var canEnable: Bool { hasBuiltIn && displayCount > 1 }

    public init(snapshot: DisplaySnapshot, connectedPhysicalCount: Int, availableSidecarCount: Int) {
        hasBuiltIn = snapshot.builtIn != nil
        let visiblePhysical = snapshot.externalDisplays.filter { !$0.isSidecar && ($0.isActive || $0.isOnline) }.count
        displayCount = (hasBuiltIn ? 1 : 0) + max(visiblePhysical, connectedPhysicalCount) + max(0, availableSidecarCount)
    }
}
