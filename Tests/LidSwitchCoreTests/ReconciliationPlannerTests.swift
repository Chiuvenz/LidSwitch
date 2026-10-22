import LidSwitchCore
import Testing

struct ReconciliationPlannerTests {
    private let planner = ReconciliationPlanner()

    @Test func builtInDefaultLeavesExternalDisplaysAloneWhenOpen() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [builtIn(active: true), external(id: 2, active: true)]
        )

        #expect(planner.nextStep(for: snapshot) == .stable(
            reason: "使用内建显示器；其他屏幕交给 macOS 管理"
        ))
    }

    @Test func builtInDefaultLeavesSystemConfigurationAloneWhenClosed() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [builtIn(active: false), external(id: 2, active: true)]
        )

        #expect(planner.nextStep(for: snapshot) == .stable(
            reason: "未选择受控外屏；保留系统显示器配置"
        ))
    }

    @Test func selectedExternalIsEnabledWhenClosed() {
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
            selectedExternalIDs: [3]
        ) == .enable(
            ids: [3],
            reason: "合盖后启用合盖组显示器"
        ))
    }

    @Test func onlySelectedExternalIsDisabledWhenOpen() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [
                builtIn(active: true),
                external(id: 3, active: true),
                external(id: 4, active: true)
            ]
        )

        #expect(planner.nextStep(
            for: snapshot,
            selectedExternalIDs: [3]
        ) == .disable(
            ids: [3],
            reason: "开盖组就绪后停用合盖组显示器"
        ))
    }

    @Test func openLidEnablesBuiltInBeforeDisablingSelectedExternal() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [builtIn(active: false), external(id: 3, active: true)]
        )

        #expect(planner.nextStep(
            for: snapshot,
            selectedExternalIDs: [3]
        ) == .enable(
            ids: [1],
            reason: "先启用 MacBook 内建显示器"
        ))
    }

    @Test func unavailableSelectedExternalBlocksClosedLidSwitch() {
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [builtIn(active: false), external(id: 2, active: true)]
        )

        #expect(planner.nextStep(
            for: snapshot,
            selectedExternalIDs: [3]
        ) == .blocked(
            reason: "合盖组没有可用的普通外屏，保留当前显示器"
        ))
    }

    @Test func placeholderDisplayIsNeverSelected() {
        let placeholder = DisplayRecord(
            id: 3,
            vendor: 0,
            model: 0,
            serial: 0,
            isBuiltIn: false,
            isActive: true,
            isOnline: true,
            isMain: false
        )
        let snapshot = DisplaySnapshot(
            lid: .closed,
            displays: [builtIn(active: false), placeholder]
        )

        #expect(planner.nextStep(
            for: snapshot,
            selectedExternalIDs: [3]
        ) == .blocked(
            reason: "合盖组没有可用的普通外屏，保留当前显示器"
        ))
    }

    @Test func missingBuiltInBlocksOpenLidSwitch() {
        let snapshot = DisplaySnapshot(
            lid: .open,
            displays: [external(id: 3, active: true)]
        )

        #expect(planner.nextStep(
            for: snapshot,
            selectedExternalIDs: [3]
        ) == .blocked(
            reason: "无法识别 MacBook 内建显示器"
        ))
    }

    @Test func allParticipatingExternalsAreDisabledAfterBuiltInIsReady() {
        let snapshot = DisplaySnapshot(lid: .open, displays: [
            builtIn(active: true), external(id: 3, active: true),
            external(id: 4, active: true), external(id: 5, active: true)
        ])
        #expect(planner.nextStep(for: snapshot, selectedExternalIDs: [3, 4]) == .disable(
            ids: [3, 4], reason: "开盖组就绪后停用合盖组显示器"
        ))
    }

    @Test func secondParticipatingExternalIsRestoredEvenWhenFirstIsAlreadyActive() {
        let snapshot = DisplaySnapshot(lid: .closed, displays: [
            builtIn(active: false), external(id: 3, active: true),
            external(id: 4, active: false), external(id: 2, active: false)
        ])
        #expect(planner.nextStep(for: snapshot, selectedExternalIDs: [3, 4]) == .enable(
            ids: [4], reason: "合盖后启用合盖组显示器"
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

    private func external(id: UInt32, active: Bool) -> DisplayRecord {
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
