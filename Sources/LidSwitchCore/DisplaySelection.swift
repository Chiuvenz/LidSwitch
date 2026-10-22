import Foundation

public struct ExternalDisplaySelection: Codable, Equatable, Sendable {
    public let selectionID: UUID
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var lastDisplayID: UInt32
    public var name: String
    public var sidecarDeviceID: String?
    public var group: DisplayGroup

    public var isSidecar: Bool {
        sidecarDeviceID != nil || (vendor == SidecarIdentity.displayVendor && model == SidecarIdentity.displayModel)
    }

    public init(display: DisplayRecord, name: String, group: DisplayGroup = .closed) {
        selectionID = UUID()
        vendor = display.vendor
        model = display.model
        serial = display.serial
        lastDisplayID = display.id
        self.name = name
        sidecarDeviceID = nil
        self.group = group
    }

    public init(sidecarDeviceID: String, name: String, group: DisplayGroup = .closed) {
        selectionID = UUID()
        vendor = SidecarIdentity.displayVendor
        model = SidecarIdentity.displayModel
        serial = SidecarIdentity.displaySerial(for: sidecarDeviceID) ?? 0
        lastDisplayID = 0
        self.name = name
        self.sidecarDeviceID = sidecarDeviceID
        self.group = group
    }

    private enum CodingKeys: String, CodingKey {
        case selectionID, vendor, model, serial, lastDisplayID, name, sidecarDeviceID, group
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectionID = try values.decodeIfPresent(UUID.self, forKey: .selectionID) ?? UUID()
        vendor = try values.decode(UInt32.self, forKey: .vendor)
        model = try values.decode(UInt32.self, forKey: .model)
        serial = try values.decode(UInt32.self, forKey: .serial)
        lastDisplayID = try values.decode(UInt32.self, forKey: .lastDisplayID)
        name = try values.decode(String.self, forKey: .name)
        sidecarDeviceID = try values.decodeIfPresent(String.self, forKey: .sidecarDeviceID)
        // Previous versions only managed closed-lid external displays.
        group = try values.decodeIfPresent(DisplayGroup.self, forKey: .group) ?? .closed
    }

    public func matchesHardware(_ display: DisplayRecord) -> Bool {
        !display.isBuiltIn &&
            display.vendor == vendor &&
            display.model == model &&
            display.serial == serial
    }

    public mutating func update(display: DisplayRecord, name: String? = nil) {
        vendor = display.vendor
        model = display.model
        serial = display.serial
        lastDisplayID = display.id
        if let name, !name.isEmpty {
            self.name = name
        }
    }
}

public struct DisplaySelectionResolver: Sendable {
    public init() {}

    public func resolve(
        _ selection: ExternalDisplaySelection,
        in snapshot: DisplaySnapshot,
        controlledOfflineIDs: Set<UInt32> = []
    ) -> DisplayRecord? {
        let externals = snapshot.externalDisplays

        if let exactVisible = externals.first(where: {
            $0.id == selection.lastDisplayID && selection.matchesHardware($0) &&
                ($0.isActive || $0.isOnline)
        }) {
            return exactVisible
        }

        let visibleHardwareMatches = externals.filter {
            selection.matchesHardware($0) && ($0.isActive || $0.isOnline)
        }
        if visibleHardwareMatches.count == 1 {
            return visibleHardwareMatches[0]
        }

        if let exactControlled = externals.first(where: {
            $0.id == selection.lastDisplayID && selection.matchesHardware($0) &&
                controlledOfflineIDs.contains($0.id)
        }) {
            return exactControlled
        }

        return nil
    }

    /// Reserve exact IDs first so two same-model selections cannot resolve to
    /// the same monitor when one of them is unplugged or reassigned.
    public func resolveAll(
        _ selections: [ExternalDisplaySelection],
        in snapshot: DisplaySnapshot,
        controlledOfflineIDs: Set<UInt32> = []
    ) -> [UUID: DisplayRecord] {
        var result: [UUID: DisplayRecord] = [:]
        var used: Set<UInt32> = []
        for selection in selections {
            if let exact = snapshot.externalDisplays.first(where: {
                $0.id == selection.lastDisplayID && selection.matchesHardware($0) &&
                    ($0.isActive || $0.isOnline)
            }), !used.contains(exact.id) {
                result[selection.selectionID] = exact
                used.insert(exact.id)
            }
        }
        for selection in selections where result[selection.selectionID] == nil {
            let controlled = snapshot.externalDisplays.first(where: {
                $0.id == selection.lastDisplayID && selection.matchesHardware($0) &&
                    controlledOfflineIDs.contains($0.id) && !used.contains($0.id)
            })
            let candidates = snapshot.externalDisplays.filter {
                !used.contains($0.id) && selection.matchesHardware($0) &&
                    ($0.isActive || $0.isOnline)
            }
            // Do not guess between multiple saved selections with the same
            // hardware identity and no surviving exact ID.
            let unresolvedPeers = selections.filter {
                result[$0.selectionID] == nil && $0.vendor == selection.vendor &&
                    $0.model == selection.model && $0.serial == selection.serial
            }
            if candidates.count == 1 && unresolvedPeers.count == 1 {
                result[selection.selectionID] = candidates[0]
                used.insert(candidates[0].id)
            } else if let controlled {
                result[selection.selectionID] = controlled
                used.insert(controlled.id)
            }
        }
        return result
    }
}
