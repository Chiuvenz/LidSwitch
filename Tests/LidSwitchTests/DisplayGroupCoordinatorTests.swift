import Foundation
import XCTest
import LidSwitchCore
@testable import LidSwitch

private func groupRecord(_ id: UInt32, active: Bool, online: Bool? = nil) -> DisplayRecord {
    DisplayRecord(id: id, vendor: 1552, model: id, serial: id, isBuiltIn: id == 1,
                  isActive: active, isOnline: online ?? active, isMain: id == 1)
}

@MainActor
private final class GroupDisplayController: DisplayControlling {
    let isAvailable = true
    var records: [DisplayRecord] = [groupRecord(1, active: false), groupRecord(3, active: true), groupRecord(4, active: false, online: true)]
    var operations: [String] = []
    var attachedPhysicalCount: Int?
    func connectedPhysicalDisplayCount() -> Int { attachedPhysicalCount ?? records.filter { !$0.isBuiltIn && !$0.isSidecar }.count }
    func snapshot(lid: LidState) throws -> DisplaySnapshot { DisplaySnapshot(lid: lid, displays: records) }
    func setEnabled(_ enabled: Bool, displayIDs: [UInt32]) throws {
        operations.append("\(enabled ? "enable" : "disable"):\(displayIDs)")
        records = records.map { displayIDs.contains($0.id) ? groupRecord($0.id, active: enabled) : $0 }
    }
    func restore(lid: LidState, externalIDs: Set<UInt32>) throws {
        let ids = externalIDs.union(lid == .open ? [1] : []).sorted()
        if !ids.isEmpty { try setEnabled(true, displayIDs: ids) }
    }
}

@MainActor
private final class GroupSidecarClient: SidecarClient {
    let isAvailable = true
    let identifier = "12345678-1234-4ABC-8DEF-1234567890AB"
    var connected = false
    var calls: [Bool] = []
    var discoverable = true
    func devices() throws -> [SidecarDeviceInfo] { discoverable ? [SidecarDeviceInfo(identifier: identifier, name: "iPad", isConnected: connected)] : [] }
    func setConnected(_ connected: Bool, identifier: String, completion: @escaping (Error?) -> Void) throws {
        self.connected = connected
        calls.append(connected)
        completion(nil)
    }
}

@MainActor
final class DisplayGroupCoordinatorTests: XCTestCase {
    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    func testBothDirectionsAndReleasingOneDisplayPreservesOtherGroup() async throws {
        let display = GroupDisplayController()
        let sidecar = SidecarSessionController(client: GroupSidecarClient())
        let selections = [
            ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Closed", group: .closed),
            ExternalDisplaySelection(display: groupRecord(4, active: true), name: "Open", group: .open)
        ]
        var lid = LidState.open
        let sut = SwitchCoordinator(controller: display, selections: selections, sidecar: sidecar, readLid: { lid }, reconciliationDelay: 0.001)
        sut.reconcile(trigger: "test open", automatic: true)
        await settle()
        XCTAssertEqual(display.operations, ["enable:[1]", "enable:[4]", "disable:[3]"])
        display.operations.removeAll()
        lid = .closed
        display.records[0] = groupRecord(1, active: false)
        sut.reconcile(trigger: "test closed", automatic: true)
        await settle()
        XCTAssertEqual(display.operations, ["enable:[3]", "disable:[4]"])
        let entries = try sut.displayMenuEntries(namesByID: [:])
        let openEntry = try XCTUnwrap(entries.first { $0.id == 4 })
        XCTAssertEqual(openEntry.group, .open)
        XCTAssertTrue(openEntry.isControlledOffline)
        try sut.setGroup(.unmanaged, for: openEntry)
        let updated = try sut.displayMenuEntries(namesByID: [:])
        XCTAssertEqual(updated.first { $0.id == 4 }?.group, .unmanaged)
        XCTAssertEqual(updated.first { $0.id == 3 }?.group, .closed)
        XCTAssertEqual(updated.first { $0.id == 3 }?.selectionID, selections[0].selectionID)
        XCTAssertEqual(display.operations.last, "enable:[4]")
    }

    func testMovingGroupKeepsStableIdentityAndOfflineAssignments() throws {
        let display = GroupDisplayController()
        display.records = [groupRecord(1, active: true)]
        let selection = ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Offline")
        let sut = SwitchCoordinator(controller: display, selections: [selection], sidecar: SidecarSessionController(client: GroupSidecarClient()), readLid: { .open })
        let entry = try XCTUnwrap(sut.displayMenuEntries(namesByID: [:]).first { $0.id == 3 })
        XCTAssertFalse(entry.isConnected)
        try sut.setGroup(.open, for: entry)
        let updated = try XCTUnwrap(sut.displayMenuEntries(namesByID: [:]).first { $0.id == 3 })
        XCTAssertEqual(updated.group, .open)
        XCTAssertEqual(updated.selectionID, selection.selectionID)
        XCTAssertTrue(display.operations.isEmpty)
    }

    func testSidecarOpenGroupConnectsOnOpenAndDisconnectsAfterClosedPhysicalReady() async {
        let display = GroupDisplayController()
        let client = GroupSidecarClient()
        let sessions = SidecarSessionController(client: client, settleDelay: 0.001, retryDelay: 0.001)
        let selections = [
            ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Closed"),
            ExternalDisplaySelection(sidecarDeviceID: client.identifier, name: "iPad", group: .open)
        ]
        var lid = LidState.open
        let sut = SwitchCoordinator(controller: display, selections: selections, sidecar: sessions, readLid: { lid }, reconciliationDelay: 0.001)
        sut.reconcile(trigger: "open", automatic: true)
        await settle()
        XCTAssertEqual(client.calls, [true])
        display.operations.removeAll()
        lid = .closed
        display.records[0] = groupRecord(1, active: false)
        sut.reconcile(trigger: "closed", automatic: true)
        await settle()
        XCTAssertEqual(display.operations, ["enable:[3]"])
        XCTAssertEqual(client.calls, [true, false])
    }

    func testMissingClosedTargetDoesNotTurnOffOpenDisplayOrUseItForSidecar() async {
        let display = GroupDisplayController()
        display.records = [groupRecord(1, active: false), groupRecord(3, active: true)]
        let client = GroupSidecarClient()
        let selections = [
            ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Open", group: .open),
            ExternalDisplaySelection(sidecarDeviceID: client.identifier, name: "iPad", group: .closed)
        ]
        let sessions = SidecarSessionController(client: client, settleDelay: 0.001, retryDelay: 0.001)
        let sut = SwitchCoordinator(controller: display, selections: selections, sidecar: sessions, readLid: { .closed })
        sut.reconcile(trigger: "closed", automatic: true)
        await settle()
        XCTAssertTrue(display.operations.isEmpty)
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testAutomaticOffSavesGroupWithoutSwitchingAndNewScreensDefaultToUnmanaged() throws {
        let display = GroupDisplayController()
        let sut = SwitchCoordinator(controller: display, selections: [], sidecar: SidecarSessionController(client: GroupSidecarClient()), readLid: { .open })
        let entry = try XCTUnwrap(sut.displayMenuEntries(namesByID: [:]).first { $0.id == 3 })
        XCTAssertEqual(entry.group, .unmanaged)
        try sut.setGroup(.open, for: entry)
        sut.reconcile(trigger: "edit while off", automatic: false)
        XCTAssertTrue(display.operations.isEmpty)
        XCTAssertEqual(try sut.displayMenuEntries(namesByID: [:]).first { $0.id == 3 }?.group, .open)
    }

    func testPanelActivityUsesActualBuiltInAndSidecarDisplayState() throws {
        let display = GroupDisplayController()
        let client = GroupSidecarClient()
        client.connected = true
        let selection = ExternalDisplaySelection(sidecarDeviceID: client.identifier, name: "iPad")
        let sut = SwitchCoordinator(controller: display, selections: [selection], sidecar: SidecarSessionController(client: client), readLid: { .closed })
        var entries = try sut.displayMenuEntries(namesByID: [:])
        XCTAssertFalse(sut.builtInActive)
        XCTAssertFalse(try XCTUnwrap(entries.first { $0.sidecarDeviceID == client.identifier }).isActive,
                       "A connected session without an active virtual display is not displaying")
        display.records.append(DisplayRecord(
            id: 50, vendor: SidecarIdentity.displayVendor, model: SidecarIdentity.displayModel,
            serial: SidecarIdentity.displaySerial(for: client.identifier)!,
            isBuiltIn: false, isActive: true, isOnline: true, isMain: false
        ))
        display.records[0] = groupRecord(1, active: true)
        entries = try sut.displayMenuEntries(namesByID: [:])
        XCTAssertTrue(sut.builtInActive)
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.sidecarDeviceID == client.identifier }).isActive)
        client.connected = false
        entries = try sut.displayMenuEntries(namesByID: [:])
        XCTAssertFalse(try XCTUnwrap(entries.first { $0.sidecarDeviceID == client.identifier }).isActive,
                       "A stale virtual display is not a connected Sidecar session")
    }

    func testOnlyBuiltInPausesAndRestoresInactiveBuiltInWithoutEnablingGhosts() async throws {
        let display = GroupDisplayController()
        display.records = [groupRecord(1, active: false), groupRecord(3, active: false)]
        display.attachedPhysicalCount = 0
        let selection = ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Missing")
        let sut = SwitchCoordinator(controller: display, selections: [selection], sidecar: SidecarSessionController(client: GroupSidecarClient()), readLid: { .open }, reconciliationDelay: 0.001)
        sut.reconcile(trigger: "unplugged", automatic: true)
        await settle()
        XCTAssertFalse(sut.switchingAllowed)
        XCTAssertEqual(display.operations, ["enable:[1]"])
        XCTAssertEqual(try sut.displayMenuEntries(namesByID: [:]).first { $0.id == 3 }?.group, .closed)
    }

    func testDisabledButAttachedDisplayDoesNotPauseAndReconnectionRespectsUserIntent() async {
        let display = GroupDisplayController()
        display.records = [groupRecord(1, active: true), groupRecord(3, active: true)]
        let selection = ExternalDisplaySelection(display: groupRecord(3, active: true), name: "Monitor")
        let sut = SwitchCoordinator(controller: display, selections: [selection], sidecar: SidecarSessionController(client: GroupSidecarClient()), readLid: { .open }, reconciliationDelay: 0.001)
        sut.reconcile(trigger: "open", automatic: true)
        await settle()
        XCTAssertTrue(sut.switchingAllowed)
        XCTAssertEqual(display.operations, ["disable:[3]"])
        display.attachedPhysicalCount = 0
        sut.reconcile(trigger: "unplugged while disabled", automatic: true)
        await settle()
        XCTAssertFalse(sut.switchingAllowed)
        display.attachedPhysicalCount = 1
        display.records[1] = groupRecord(3, active: true)
        display.operations.removeAll()
        sut.reconcile(trigger: "reconnected while user off", automatic: false)
        await settle()
        XCTAssertTrue(sut.switchingAllowed)
        XCTAssertTrue(display.operations.isEmpty)
        sut.reconcile(trigger: "resume previous enabled intent", automatic: true)
        await settle()
        XCTAssertEqual(display.operations, ["disable:[3]"])
        XCTAssertTrue(sut.switchingAllowed)
    }

    func testDisconnectedOwnedSidecarDoesNotOscillateButSavedMissingDeviceDoesNotCount() async {
        let display = GroupDisplayController()
        display.records = [groupRecord(1, active: true)]
        let client = GroupSidecarClient()
        client.connected = true
        let sessions = SidecarSessionController(client: client, settleDelay: 0.001, retryDelay: 0.001)
        let selection = ExternalDisplaySelection(sidecarDeviceID: client.identifier, name: "iPad")
        let sut = SwitchCoordinator(controller: display, selections: [selection], sidecar: sessions, readLid: { .open }, reconciliationDelay: 0.001)
        sut.reconcile(trigger: "open", automatic: true)
        await settle()
        XCTAssertEqual(client.calls, [false])
        sut.reconcile(trigger: "session intentionally disconnected", automatic: true)
        await settle()
        XCTAssertTrue(sut.switchingAllowed)
        XCTAssertEqual(client.calls, [false])
        client.discoverable = false
        sut.reconcile(trigger: "iPad unavailable", automatic: true)
        await settle()
        XCTAssertFalse(sut.switchingAllowed)
        XCTAssertEqual(client.calls, [false])
    }
}
