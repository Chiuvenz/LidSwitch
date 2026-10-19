import LidSwitchCore
import Testing

struct ReconciliationPlannerTests {
    private let planner = ReconciliationPlanner()

    @Test func closedLidEnablesInactiveExternalDisplay() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [builtIn(active: false), external(active: false)]
        )

        #expect(planner.nextStep(for: snapshot) == .enable(
            ids: [2],
            reason: "合盖后启用外接显示器"
        ))
    }

    @Test func closedLidDoesNotEnableOfflineGhostWhenExternalIsAlreadyActive() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [
                builtIn(active: false),
                external(id: 3, active: true),
                external(id: 2, active: false)
            ]
        )

        #expect(planner.nextStep(for: snapshot) == .stable(
            reason: "合盖模式已就绪"
        ))
    }

    @Test func closedLidRestoresOnlyPreviouslyActiveExternal() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [
                builtIn(active: false),
                external(id: 3, active: false),
                external(id: 2, active: false)
            ]
        )

        #expect(planner.nextStep(
            for: snapshot,
            preferredExternalIDs: [3]
        ) == .enable(
            ids: [3],
            reason: "合盖后启用外接显示器"
        ))
    }

    @Test func closedLidFinishesRestoringMultiplePreferredExternals() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [
                builtIn(active: false),
                external(id: 3, active: true),
                external(id: 4, active: false),
                external(id: 2, active: false)
            ]
        )

        #expect(planner.nextStep(
            for: snapshot,
            preferredExternalIDs: [3, 4]
        ) == .enable(
            ids: [4],
            reason: "合盖后启用外接显示器"
        ))
    }

    @Test func openLidEnablesBuiltInBeforeDisablingExternal() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [builtIn(active: false), external(active: true)]
        )

        #expect(planner.nextStep(for: snapshot) == .enable(
            ids: [1],
            reason: "先启用 MacBook 内建显示器"
        ))
    }

    @Test func openLidDisablesExternalOnlyAfterBuiltInIsActive() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [builtIn(active: true), external(active: true)]
        )

        #expect(planner.nextStep(for: snapshot) == .disable(
            ids: [2],
            reason: "内屏就绪后停用外接显示器"
        ))
    }

    @Test func placeholderDisplayIsNeverToggled() {
        let placeholder = DisplayRecord(
            id: 3,
            vendor: 0,
            model: 0,
            serial: 0,
            isBuiltIn: false,
            isActive: false,
            isOnline: false,
            isMain: false
        )
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [builtIn(active: false), placeholder]
        )

        #expect(planner.nextStep(for: snapshot) == .stable(
            reason: "合盖，但没有检测到外接显示器"
        ))
    }

    @Test func missingBuiltInBlocksExternalDisable() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [external(active: true)]
        )

        #expect(planner.nextStep(for: snapshot) == .blocked(
            reason: "无法识别 MacBook 内建显示器"
        ))
    }

    private func builtIn(active: Bool) -> DisplayRecord {
        DisplayRecord(
            id: 1,
            vendor: 1552,
            model: 41058,
            serial: 1,
            isBuiltIn: true,
            isActive: active,
            isOnline: active,
            isMain: active
        )
    }

    private func external(id: UInt32 = 2, active: Bool) -> DisplayRecord {
        DisplayRecord(
            id: id,
            vendor: 25001,
            model: 45061,
            serial: 0,
            isBuiltIn: false,
            isActive: active,
            isOnline: active,
            isMain: active
        )
    }
}
