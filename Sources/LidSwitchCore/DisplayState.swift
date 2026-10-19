import Foundation

public enum LidState: String, Equatable, Sendable {
    case open
    case closed
    case unknown
}

public struct DisplayRecord: Equatable, Sendable {
    public let id: UInt32
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public let isBuiltIn: Bool
    public let isActive: Bool
    public let isOnline: Bool
    public let isMain: Bool

    public init(
        id: UInt32,
        vendor: UInt32,
        model: UInt32,
        serial: UInt32,
        isBuiltIn: Bool,
        isActive: Bool,
        isOnline: Bool,
        isMain: Bool
    ) {
        self.id = id
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.isOnline = isOnline
        self.isMain = isMain
    }

    /// SkyLight can contain placeholder displays with no hardware identity.
    /// Those must never be toggled automatically.
    public var isIdentifiedHardware: Bool {
        isBuiltIn || vendor != 0 || model != 0
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public let lid: LidState
    public let displays: [DisplayRecord]

    public init(lid: LidState, displays: [DisplayRecord]) {
        self.lid = lid
        self.displays = displays
    }

    public var builtIn: DisplayRecord? {
        displays.first(where: \.isBuiltIn)
    }

    public var externalDisplays: [DisplayRecord] {
        displays.filter { !$0.isBuiltIn && $0.isIdentifiedHardware }
    }
}

public enum ReconciliationStep: Equatable, Sendable {
    case enable(ids: [UInt32], reason: String)
    case disable(ids: [UInt32], reason: String)
    case stable(reason: String)
    case blocked(reason: String)
}

public struct ReconciliationPlanner: Sendable {
    public init() {}

    public func nextStep(
        for snapshot: DisplaySnapshot,
        preferredExternalIDs: Set<UInt32> = []
    ) -> ReconciliationStep {
        let externals = snapshot.externalDisplays

        switch snapshot.lid {
        case .closed:
            let preferred = externals
                .filter { preferredExternalIDs.contains($0.id) }
            if !preferred.isEmpty {
                let disabledPreferred = preferred.filter { !$0.isActive }.map(\.id)
                if !disabledPreferred.isEmpty {
                    return .enable(
                        ids: disabledPreferred,
                        reason: "合盖后启用外接显示器"
                    )
                }
                return .stable(reason: "合盖模式已就绪")
            }

            // SkyLight may keep an offline record for a display after assigning
            // the same physical monitor a new display ID. If any external is
            // already active, clamshell mode is ready and those stale records
            // must not be enabled.
            guard !externals.contains(where: \.isActive) else {
                return .stable(reason: "合盖模式已就绪")
            }

            // An online-but-inactive display is a safer fallback than a record
            // known to SkyLight only. The final fallback preserves cold-start
            // behavior where a disabled display is reported as offline.
            let online = externals.filter(\.isOnline).map(\.id)
            if !online.isEmpty {
                return .enable(ids: online, reason: "合盖后启用外接显示器")
            }

            let disabled = externals.filter { !$0.isActive }.map(\.id)
            guard !disabled.isEmpty else {
                return .stable(reason: externals.isEmpty
                    ? "合盖，但没有检测到外接显示器"
                    : "合盖模式已就绪")
            }
            return .enable(ids: disabled, reason: "合盖后启用外接显示器")

        case .open:
            guard let builtIn = snapshot.builtIn else {
                return .blocked(reason: "无法识别 MacBook 内建显示器")
            }
            guard builtIn.isActive else {
                return .enable(ids: [builtIn.id], reason: "先启用 MacBook 内建显示器")
            }

            let activeExternals = externals.filter(\.isActive).map(\.id)
            guard !activeExternals.isEmpty else {
                return .stable(reason: "开盖模式已就绪")
            }
            return .disable(ids: activeExternals, reason: "内屏就绪后停用外接显示器")

        case .unknown:
            return .blocked(reason: "暂时无法读取开合盖状态")
        }
    }
}
