import Testing
import LidSwitchCore

struct SwitchAvailabilityTests {
    private func record(_ id: UInt32, active: Bool, builtIn: Bool = false) -> DisplayRecord {
        DisplayRecord(id: id, vendor: 1552, model: 1, serial: id, isBuiltIn: builtIn, isActive: active, isOnline: active, isMain: builtIn)
    }

    @Test func onlyBuiltInOrGhostIsNotEnoughEvenWithLidClosed() {
        let snapshot = DisplaySnapshot(lid: .closed, displays: [record(1, active: false, builtIn: true), record(2, active: false)])
        let gate = SwitchAvailability(snapshot: snapshot, connectedPhysicalCount: 0, availableSidecarCount: 0)
        #expect(gate.displayCount == 1)
        #expect(!gate.canEnable)
    }

    @Test func attachedInactivePhysicalScreenCountsWithoutRequiringItToBeLit() {
        let snapshot = DisplaySnapshot(lid: .open, displays: [record(1, active: true, builtIn: true), record(2, active: false)])
        #expect(SwitchAvailability(snapshot: snapshot, connectedPhysicalCount: 1, availableSidecarCount: 0).canEnable)
    }

    @Test func visibleAndPhysicalEvidenceAreNotDoubleCounted() {
        let snapshot = DisplaySnapshot(lid: .closed, displays: [record(1, active: false, builtIn: true), record(3, active: true)])
        #expect(SwitchAvailability(snapshot: snapshot, connectedPhysicalCount: 1, availableSidecarCount: 0).displayCount == 2)
    }

    @Test func sidecarNeedsLiveEvidenceAndMissingBuiltInBlocksSwitching() {
        let snapshot = DisplaySnapshot(lid: .open, displays: [record(1, active: true, builtIn: true)])
        #expect(SwitchAvailability(snapshot: snapshot, connectedPhysicalCount: 0, availableSidecarCount: 1).canEnable)
        let missing = DisplaySnapshot(lid: .open, displays: [record(3, active: true)])
        #expect(!SwitchAvailability(snapshot: missing, connectedPhysicalCount: 1, availableSidecarCount: 1).canEnable)
    }
}
