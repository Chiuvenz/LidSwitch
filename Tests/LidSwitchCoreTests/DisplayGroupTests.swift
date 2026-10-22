import Foundation
import Testing
@testable import LidSwitchCore

struct DisplayGroupTests {
    private let planner = ReconciliationPlanner()
    private func display(_ id: UInt32, active: Bool, sidecar: Bool = false) -> DisplayRecord {
        DisplayRecord(
            id: id, vendor: sidecar ? SidecarIdentity.displayVendor : 1552,
            model: sidecar ? SidecarIdentity.displayModel : 1, serial: id,
            isBuiltIn: id == 1, isActive: active, isOnline: active, isMain: id == 1
        )
    }

    @Test func oldSelectionsMigrateToClosedGroupWithoutChangingIdentity() throws {
        let data = Data(#"{"selectionID":"11111111-1111-1111-1111-111111111111","vendor":1552,"model":1,"serial":3,"lastDisplayID":3,"name":"Monitor"}"#.utf8)
        let selection = try JSONDecoder().decode(ExternalDisplaySelection.self, from: data)
        #expect(selection.group == .closed)
        #expect(selection.selectionID.uuidString == "11111111-1111-1111-1111-111111111111")
        var updated = selection
        updated.group = .open
        let decoded = try JSONDecoder().decode(ExternalDisplaySelection.self, from: JSONEncoder().encode(updated))
        #expect(decoded == updated)
        #expect(decoded.selectionID == selection.selectionID)
    }

    @Test func allGroupValuesRoundTripAndUnknownLidNeverMatches() throws {
        for group in DisplayGroup.allCases {
            #expect(try JSONDecoder().decode(DisplayGroup.self, from: JSONEncoder().encode(group)) == group)
            #expect(!group.matches(.unknown))
        }
        #expect(DisplayGroup.open.matches(.open))
        #expect(DisplayGroup.closed.matches(.closed))
        #expect(!DisplayGroup.unmanaged.matches(.open))
        #expect(!DisplayGroup.unmanaged.matches(.closed))
    }

    @Test func openEnablesBuiltInThenOpenExternalsBeforeDisablingClosedGroup() {
        let groups: [UInt32: DisplayGroup] = [3: .closed, 4: .open, 5: .unmanaged]
        let old = [display(1, active: false), display(3, active: true), display(4, active: false), display(5, active: true)]
        #expect(planner.nextStep(for: DisplaySnapshot(lid: .open, displays: old), groups: groups) == .enable(ids: [1], reason: "先启用 MacBook 内建显示器"))
        let builtinReady = [display(1, active: true)] + Array(old.dropFirst())
        #expect(planner.nextStep(for: DisplaySnapshot(lid: .open, displays: builtinReady), groups: groups) == .enable(ids: [4], reason: "开盖后启用开盖组显示器"))
        let ready = [display(1, active: true), display(3, active: true), display(4, active: true), display(5, active: true)]
        #expect(planner.nextStep(for: DisplaySnapshot(lid: .open, displays: ready), groups: groups) == .disable(ids: [3], reason: "开盖组就绪后停用合盖组显示器"))
    }

    @Test func closedEnablesAllTargetsBeforeDisablingAnyOpenGroupScreens() {
        let groups: [UInt32: DisplayGroup] = [3: .closed, 4: .open, 6: .closed]
        let transition = DisplaySnapshot(lid: .closed, displays: [display(3, active: true), display(4, active: true), display(6, active: false)])
        #expect(planner.nextStep(for: transition, groups: groups) == .enable(ids: [6], reason: "合盖后启用合盖组显示器"))
        let ready = DisplaySnapshot(lid: .closed, displays: [display(3, active: true), display(4, active: true), display(6, active: true)])
        #expect(planner.nextStep(for: ready, groups: groups) == .disable(ids: [4], reason: "合盖组就绪后停用开盖组显示器"))
    }

    @Test func missingOrEmptyClosedGroupPreservesOpenGroup() {
        let state = DisplaySnapshot(lid: .closed, displays: [display(4, active: true)])
        for groups: [UInt32: DisplayGroup] in [[4: .open], [3: .closed, 4: .open]] {
            guard case .blocked = planner.nextStep(for: state, groups: groups) else {
                Issue.record("Missing target must never disable the remaining display")
                continue
            }
        }
    }

    @Test func unknownLidAndSidecarAreNeverPhysicalTransactions() {
        let state = DisplaySnapshot(lid: .unknown, displays: [display(1, active: true), display(3, active: true)])
        #expect(planner.nextStep(for: state, groups: [3: .closed]) == .blocked(reason: "暂时无法读取开合盖状态"))
        let closed = DisplaySnapshot(lid: .closed, displays: [display(4, active: true), display(49, active: true, sidecar: true)])
        guard case .blocked = planner.nextStep(for: closed, groups: [4: .open, 49: .closed]) else {
            Issue.record("A virtual target cannot justify disabling the last physical screen")
            return
        }
    }

    @Test func sidecarCanFollowEitherGroupButRequiresSafeDisplay() {
        let policy = SidecarPolicy()
        #expect(policy.goal(lid: .open, builtInActive: true, externalActive: false, group: .open) == .connect)
        #expect(policy.goal(lid: .closed, builtInActive: false, externalActive: true, group: .open) == .disconnect)
        #expect(policy.goal(lid: .closed, builtInActive: false, externalActive: false, group: .open) == nil)
        #expect(policy.goal(lid: .open, builtInActive: false, externalActive: true, group: .open) == nil)
        #expect(policy.goal(lid: .open, builtInActive: true, externalActive: true, group: .unmanaged) == nil)
    }

    @Test func everyPhysicalStateKeepsUnmanagedScreensUntouchedAndNeverDisablesLastScreen() {
        for lid: LidState in [.open, .closed] {
            for bits in 0..<8 {
                let displays = [display(1, active: bits & 1 != 0), display(3, active: bits & 2 != 0), display(4, active: bits & 4 != 0)]
                for first in DisplayGroup.allCases {
                    for second in DisplayGroup.allCases {
                        let groups: [UInt32: DisplayGroup] = [3: first, 4: second]
                        let step = planner.nextStep(for: DisplaySnapshot(lid: lid, displays: displays), groups: groups)
                        switch step {
                        case .disable(let ids, _):
                            #expect(displays.contains { $0.isActive && !ids.contains($0.id) })
                            #expect(ids.allSatisfy { groups[$0] != .unmanaged && groups[$0]?.matches(lid) == false })
                        case .enable(let ids, _):
                            #expect(ids.allSatisfy { $0 == 1 ? lid == .open : groups[$0]?.matches(lid) == true })
                        case .stable, .blocked: break
                        }
                    }
                }
            }
        }
    }
}
