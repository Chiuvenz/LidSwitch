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

    public var isSidecar: Bool {
        vendor == SidecarIdentity.displayVendor && model == SidecarIdentity.displayModel
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
        selectedExternalIDs: Set<UInt32>? = nil
    ) -> ReconciliationStep {
        nextStep(
            for: snapshot,
            groups: Dictionary(uniqueKeysWithValues: (selectedExternalIDs ?? []).map { ($0, .closed) }),
            hasConfiguredDisplays: selectedExternalIDs != nil
        )
    }

    public func nextStep(
        for snapshot: DisplaySnapshot,
        groups: [UInt32: DisplayGroup],
        hasConfiguredDisplays: Bool = false
    ) -> ReconciliationStep {
        guard snapshot.lid != .unknown else {
            return .blocked(reason: "暂时无法读取开合盖状态")
        }
        let managed = snapshot.externalDisplays.filter {
            !$0.isSidecar && groups[$0.id] != nil && groups[$0.id] != .unmanaged
        }
        let targets = managed.filter { groups[$0.id]?.matches(snapshot.lid) == true }
        let toEnable = targets.filter { !$0.isActive }.map(\.id).sorted()
        let toDisable = managed.filter {
            groups[$0.id]?.matches(snapshot.lid) == false && $0.isActive
        }.map(\.id).sorted()

        switch snapshot.lid {
        case .closed:
            if !hasConfiguredDisplays && groups.isEmpty {
                return .stable(reason: "未选择受控外屏；保留系统显示器配置")
            }
            if !toEnable.isEmpty {
                return .enable(ids: toEnable, reason: "合盖后启用合盖组显示器")
            }
            // Never use an open-group or virtual display as justification to
            // turn off the last physical screen during a closed-lid switch.
            guard targets.contains(where: \.isActive) else {
                return .blocked(reason: "合盖组没有可用的普通外屏，保留当前显示器")
            }
            if !toDisable.isEmpty {
                return .disable(ids: toDisable, reason: "合盖组就绪后停用开盖组显示器")
            }
            return .stable(reason: "合盖组已就绪")

        case .open:
            guard let builtIn = snapshot.builtIn else {
                return .blocked(reason: "无法识别 MacBook 内建显示器")
            }
            guard builtIn.isActive else {
                return .enable(ids: [builtIn.id], reason: "先启用 MacBook 内建显示器")
            }

            if !toEnable.isEmpty {
                return .enable(ids: toEnable, reason: "开盖后启用开盖组显示器")
            }
            guard !toDisable.isEmpty else {
                return .stable(reason: groups.isEmpty && !hasConfiguredDisplays
                    ? "使用内建显示器；其他屏幕交给 macOS 管理"
                    : "开盖组已就绪")
            }
            return .disable(ids: toDisable, reason: "开盖组就绪后停用合盖组显示器")

        case .unknown:
            return .blocked(reason: "暂时无法读取开合盖状态")
        }
    }
}
