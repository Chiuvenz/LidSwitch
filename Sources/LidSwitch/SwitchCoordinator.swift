import Foundation
import LidSwitchCore
import OSLog

struct DisplayMenuEntry {
    let id: UInt32
    let selectionID: UUID?
    let name: String
    let isActive: Bool
    let isConnected: Bool
    let isControlledOffline: Bool
    let group: DisplayGroup
    var sidecarDeviceID: String? = nil
    var detailOverride: String? = nil
}

@MainActor
final class SwitchCoordinator {
    private let controller: any DisplayControlling
    private let readLid: () -> LidState
    private let reconciliationDelay: TimeInterval
    private let planner = ReconciliationPlanner()
    private let resolver = DisplaySelectionResolver()
    private let sidecar: SidecarSessionController
    private let sidecarPolicy = SidecarPolicy()
    private let logger = Logger(subsystem: "local.chiu.LidSwitch", category: "switch")
    private var generation = 0
    private var selections: [ExternalDisplaySelection]
    private var controlledOfflineIDs: Set<UInt32> = []
    private var automaticEnabled = false
    private var lastLid: LidState = .unknown
    private(set) var builtInActive = false
    private(set) var switchingAllowed = false

    var onStatusChange: ((String) -> Void)?
    var onSelectionChange: (([ExternalDisplaySelection]) -> Void)?
    var onDisplayChange: (() -> Void)?

    init(
        controller: any DisplayControlling, selections: [ExternalDisplaySelection],
        sidecar: SidecarSessionController? = nil,
        readLid: @escaping () -> LidState = { LidStateReader.read() },
        reconciliationDelay: TimeInterval = 0.6
    ) {
        self.controller = controller
        self.readLid = readLid
        self.reconciliationDelay = reconciliationDelay
        self.selections = selections.filter { $0.group != .unmanaged }
        self.sidecar = sidecar ?? SidecarSessionController(client: SidecarBridge())
        self.sidecar.onChange = { [weak self] in self?.onDisplayChange?() }
        self.sidecar.onStatus = { [weak self] status in self?.onStatusChange?(status) }
        self.sidecar.canPerformAutomatic = { [weak self] goal in
            guard let self, self.automaticEnabled else { return false }
            let lid = self.readLid()
            guard let snapshot = try? self.controller.snapshot(lid: lid) else { return false }
            return self.availability(in: snapshot).canEnable && self.sidecarGoal(in: snapshot) == goal
        }
    }

    func reconcile(trigger: String, automatic: Bool) {
        generation += 1
        let lid = readLid()
        if automaticEnabled != automatic {
            sidecar.resetRetries()
        }
        if lid != lastLid || !automatic { sidecar.pauseAutomatic() }
        lastLid = lid
        automaticEnabled = automatic
        logger.info("Reconcile: \(trigger, privacy: .public)")
        runStep(generation: generation, attempt: 0, automatic: automatic)
    }

    func setGroup(_ group: DisplayGroup, for entry: DisplayMenuEntry) throws {
        generation += 1
        sidecar.pauseAutomatic()
        sidecar.resetRetries()
        let snapshot = try controller.snapshot(lid: readLid())
        updateSelections(in: snapshot)
        if let selectionID = entry.selectionID,
           let index = selections.firstIndex(where: { $0.selectionID == selectionID }) {
            if group != .unmanaged {
                selections[index].group = group
                onSelectionChange?(selections)
                return
            }
            if selections[index].isSidecar {
                if let id = selections[index].sidecarDeviceID { sidecar.release(identifier: id) }
                selections.remove(at: index)
                onSelectionChange?(selections)
                return
            }
            let resolved = resolver.resolveAll(
                selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
            )[selectionID]
            // Release only this monitor when it stops participating. Other
            // selections and their disabled state remain intact.
            if let resolved, controlledOfflineIDs.contains(resolved.id) {
                try controller.setEnabled(true, displayIDs: [resolved.id])
                controlledOfflineIDs.remove(resolved.id)
            }
            selections.remove(at: index)
        } else if group == .unmanaged {
            return
        } else if let identifier = entry.sidecarDeviceID {
            guard !selections.contains(where: \.isSidecar) else { throw SidecarError.tooManyDevices }
            guard try sidecar.client.devices().contains(where: { $0.identifier == identifier }) else {
                throw SidecarError.deviceUnavailable
            }
            selections.append(ExternalDisplaySelection(sidecarDeviceID: identifier, name: entry.name, group: group))
        } else {
            guard let display = snapshot.externalDisplays.first(where: {
                $0.id == entry.id && !$0.isSidecar && ($0.isActive || $0.isOnline)
            }) else {
                throw DisplayControllerError.displayUnavailable
            }
            guard !selections.contains(where: { $0.lastDisplayID == display.id }) else { return }
            selections.append(ExternalDisplaySelection(display: display, name: entry.name, group: group))
        }
        onSelectionChange?(selections)
    }

    func restoreManagedDisplays() {
        generation += 1
        automaticEnabled = false
        sidecar.restore()
        do {
            let lid = readLid()
            let snapshot = try controller.snapshot(lid: lid)
            let resolved = resolver.resolveAll(
                selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
            )
            let ids = Set(resolved.values.map(\.id)).intersection(controlledOfflineIDs)
            try controller.restore(lid: lid, externalIDs: ids)
            controlledOfflineIDs.subtract(ids)
            onStatusChange?("已恢复参与切换的显示器")
        } catch {
            onStatusChange?("恢复失败：\(error.localizedDescription)")
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var hasOutstandingRecovery: Bool { sidecar.hasOutstandingRecovery }

    func suspendForSleep() {
        generation += 1
        automaticEnabled = false
        sidecar.suspend()
    }

    func currentStatus() -> String {
        do {
            let snapshot = try controller.snapshot(lid: readLid())
            updateSelections(in: snapshot)
            return describe(snapshot)
        } catch {
            return "状态不可用：\(error.localizedDescription)"
        }
    }

    func displayMenuEntries(namesByID: [UInt32: String]) throws -> [DisplayMenuEntry] {
        let snapshot = try controller.snapshot(lid: readLid())
        builtInActive = snapshot.builtIn?.isActive == true
        switchingAllowed = availability(in: snapshot).canEnable
        updateSelections(in: snapshot, namesByID: namesByID)
        let resolved = resolver.resolveAll(
            selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
        )
        let visible = snapshot.externalDisplays.filter { !$0.isSidecar && ($0.isActive || $0.isOnline) }
        var entries = visible.map { display -> DisplayMenuEntry in
            let selection = selections.first { resolved[$0.selectionID]?.id == display.id }
            return DisplayMenuEntry(
                id: display.id,
                selectionID: selection?.selectionID,
                name: namesByID[display.id] ?? selection?.name ?? "外接显示器 \(display.vendor):\(display.model)",
                isActive: display.isActive,
                isConnected: true,
                isControlledOffline: false,
                group: selection?.group ?? .unmanaged
            )
        }
        for selection in selections where !selection.isSidecar {
            let display = resolved[selection.selectionID]
            guard !visible.contains(where: { $0.id == display?.id }) else { continue }
            entries.append(DisplayMenuEntry(
                id: display?.id ?? selection.lastDisplayID,
                selectionID: selection.selectionID,
                name: selection.name,
                isActive: false,
                isConnected: false,
                isControlledOffline: display.map { controlledOfflineIDs.contains($0.id) } ?? false,
                group: selection.group
            ))
        }
        let devices = (try? sidecar.client.devices()) ?? []
        for device in devices {
            let selection = selections.first { $0.sidecarDeviceID == device.identifier }
            let display = snapshot.externalDisplays.first {
                $0.isSidecar && $0.serial == SidecarIdentity.displaySerial(for: device.identifier) && ($0.isActive || $0.isOnline)
            }
            entries.append(DisplayMenuEntry(
                id: display?.id ?? 0,
                selectionID: selection?.selectionID,
                name: device.name,
                isActive: device.isConnected && display?.isActive == true,
                isConnected: device.isConnected,
                isControlledOffline: sidecar.disconnectedByApp.contains(device.identifier),
                group: selection?.group ?? .unmanaged,
                sidecarDeviceID: device.identifier,
                detailOverride: sidecar.detail(for: device)
            ))
        }
        for selection in selections where selection.isSidecar && !devices.contains(where: { $0.identifier == selection.sidecarDeviceID }) {
            entries.append(DisplayMenuEntry(
                id: 0, selectionID: selection.selectionID, name: selection.name,
                isActive: false, isConnected: false, isControlledOffline: false, group: selection.group,
                sidecarDeviceID: selection.sidecarDeviceID,
                detailOverride: "随航 · 实验性 · iPad 不可用"
            ))
        }
        return entries.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func runStep(generation: Int, attempt: Int, automatic: Bool) {
        guard generation == self.generation else { return }
        guard attempt < 16 else {
            onStatusChange?("切换超时，可关闭“自动切换”恢复显示器")
            logger.error("Reconciliation timed out")
            return
        }
        do {
            let snapshot = try controller.snapshot(lid: readLid())
            switchingAllowed = availability(in: snapshot).canEnable
            updateSelections(in: snapshot)
            onStatusChange?(describe(snapshot))
            let resolved = resolver.resolveAll(
                selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
            )
            let groups = Dictionary(uniqueKeysWithValues: selections.compactMap { selection -> (UInt32, DisplayGroup)? in
                guard let display = resolved[selection.selectionID] else { return nil }
                return (display.id, selection.group)
            })
            guard automatic else { return }
            guard switchingAllowed else {
                automaticEnabled = false
                sidecar.pauseAutomatic()
                // Pause without forgetting user intent or reconnecting stale
                // external IDs. The built-in remains the open-lid fallback.
                if snapshot.lid == .open, let builtIn = snapshot.builtIn, !builtIn.isActive {
                    try controller.setEnabled(true, displayIDs: [builtIn.id])
                }
                onStatusChange?("可用屏幕不足，已暂停自动切换；连接外屏后恢复")
                return
            }
            switch planner.nextStep(for: snapshot, groups: groups, hasConfiguredDisplays: !selections.isEmpty) {
            case .enable(let ids, let reason):
                sidecar.pauseAutomatic()
                logger.info("\(reason, privacy: .public): \(ids.description, privacy: .public)")
                try controller.setEnabled(true, displayIDs: ids)
                scheduleNext(generation: generation, attempt: attempt + 1)
            case .disable(let ids, let reason):
                sidecar.pauseAutomatic()
                logger.info("\(reason, privacy: .public): \(ids.description, privacy: .public)")
                controlledOfflineIDs.formUnion(ids)
                try controller.setEnabled(false, displayIDs: ids)
                scheduleNext(generation: generation, attempt: attempt + 1)
            case .stable(let reason):
                onStatusChange?("\(describe(snapshot)) · \(reason)")
                reconcileSidecar(in: snapshot)
            case .blocked(let reason):
                onStatusChange?("\(reason) · 其他屏幕保持系统配置")
                reconcileSidecar(in: snapshot)
            }
        } catch let error as DisplayControllerError where error.isRetryable {
            onStatusChange?("显示器正在重新配置，正在重试（\(attempt + 1)/16）")
            scheduleNext(generation: generation, attempt: attempt + 1)
        } catch {
            onStatusChange?("切换失败：\(error.localizedDescription)")
            logger.error("Reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleNext(generation: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + reconciliationDelay) { [weak self] in
            self?.runStep(generation: generation, attempt: attempt, automatic: true)
        }
    }

    private func updateSelections(in snapshot: DisplaySnapshot, namesByID: [UInt32: String] = [:]) {
        let resolved = resolver.resolveAll(
            selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
        )
        let previous = selections
        let devices = (try? sidecar.client.devices()) ?? []
        for index in selections.indices {
            if selections[index].isSidecar {
                let matches = devices.filter {
                    if let id = selections[index].sidecarDeviceID { return $0.identifier == id }
                    return selections[index].serial != 0 && SidecarIdentity.displaySerial(for: $0.identifier) == selections[index].serial
                }
                if matches.count == 1 {
                    selections[index].sidecarDeviceID = matches[0].identifier
                    selections[index].name = matches[0].name
                }
                continue
            }
            guard let display = resolved[selections[index].selectionID] else { continue }
            let oldID = selections[index].lastDisplayID
            selections[index].update(display: display, name: namesByID[display.id])
            if display.isActive { controlledOfflineIDs.remove(display.id) }
            if oldID != display.id {
                controlledOfflineIDs.remove(oldID)
            }
        }
        if selections != previous { onSelectionChange?(selections) }
    }

    private func reconcileSidecar(in snapshot: DisplaySnapshot) {
        guard let selected = selections.first(where: \.isSidecar),
              let identifier = selected.sidecarDeviceID else {
            sidecar.pauseAutomatic()
            return
        }
        guard let goal = sidecarGoal(in: snapshot) else {
            sidecar.pauseAutomatic()
            return
        }
        sidecar.setAutomaticGoal(goal, identifier: identifier)
    }

    private func sidecarGoal(in snapshot: DisplaySnapshot) -> SidecarGoal? {
        guard let selected = selections.first(where: \.isSidecar) else { return nil }
        let resolved = resolver.resolveAll(
            selections.filter { !$0.isSidecar }, in: snapshot, controlledOfflineIDs: controlledOfflineIDs
        )
        let openGroupIDs = Set(selections.filter { $0.group == .open }.compactMap { resolved[$0.selectionID]?.id })
        return sidecarPolicy.goal(
            lid: snapshot.lid,
            builtInActive: snapshot.builtIn?.isActive == true,
            externalActive: snapshot.externalDisplays.contains {
                $0.isActive && !$0.isSidecar && !openGroupIDs.contains($0.id)
            },
            group: selected.group
        )
    }

    private func availability(in snapshot: DisplaySnapshot) -> SwitchAvailability {
        let devices = (try? sidecar.client.devices()) ?? []
        let availableSidecars = devices.filter {
            $0.isConnected || sidecar.disconnectedByApp.contains($0.identifier)
        }.count
        return SwitchAvailability(
            snapshot: snapshot,
            connectedPhysicalCount: controller.connectedPhysicalDisplayCount(),
            availableSidecarCount: availableSidecars
        )
    }

    private func describe(_ snapshot: DisplaySnapshot) -> String {
        let lidText = snapshot.lid == .closed ? "已合盖" : snapshot.lid == .open ? "已开盖" : "盖子状态未知"
        return "\(lidText) · 内建屏 + \(selections.count) 台外屏参与切换"
    }
}
