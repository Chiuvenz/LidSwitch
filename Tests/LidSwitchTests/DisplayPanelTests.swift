import AppKit
import XCTest
import LidSwitchCore
@testable import LidSwitch

@MainActor
final class DisplayPanelTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    func testCapsulePickerAndBuiltInUseSameControlWithLockedAssignment() {
        _ = NSApplication.shared
        let panel = DisplayPanelController()
        let entry = DisplayMenuEntry(id: 3, selectionID: nil, name: "A very long external display name", isActive: true, isConnected: true, isControlledOffline: false, group: .closed)
        panel.update(entries: [entry], builtInActive: false, automatic: true, login: false, available: true)
        let pickers = descendants(panel.view).compactMap { $0 as? DisplayGroupPicker }
        XCTAssertEqual(pickers.count, 2, "Built-in and external displays use a consistent control")
        XCTAssertEqual(pickers.first?.selectedGroup, .open)
        XCTAssertTrue(pickers.first?.isFixed == true)
        XCTAssertTrue(pickers.first?.buttons.allSatisfy { !$0.isEnabled } == true)
        XCTAssertEqual(pickers.last?.buttons.count, 3)
        XCTAssertEqual(pickers.last?.selectedGroup, .closed)
        XCTAssertEqual(panel.preferredContentSize.width, 480)
        XCTAssertEqual(pickers.last?.buttons.map(\.title), ["开盖显示", "合盖显示", "交给系统"])
        XCTAssertGreaterThan(panel.preferredContentSize.height, 200)
        var received: DisplayGroup?
        panel.onChangeGroup = { _, group in received = group }
        pickers.last?.buttons.first?.performClick(nil)
        XCTAssertEqual(received, .open)
        received = nil
        pickers.first?.buttons.last?.performClick(nil)
        XCTAssertNil(received)
        XCTAssertEqual(pickers.first?.selectedGroup, .open)
    }

    func testManyScreensAreScrollableAndUnavailableAPIIsReadOnly() {
        _ = NSApplication.shared
        let panel = DisplayPanelController()
        let entries = (0..<12).map { index in
            DisplayMenuEntry(id: UInt32(index + 3), selectionID: nil, name: "Monitor \(index)", isActive: true, isConnected: true, isControlledOffline: false, group: .unmanaged)
        }
        panel.update(entries: entries, builtInActive: true, automatic: false, login: false, available: false)
        let views = descendants(panel.view)
        let pickers = views.compactMap { $0 as? DisplayGroupPicker }
        XCTAssertEqual(pickers.count, 13)
        XCTAssertTrue(pickers.allSatisfy { !$0.isEnabled })
        XCTAssertLessThanOrEqual(views.compactMap { $0 as? NSScrollView }.first?.frame.height ?? 1000, 336)
    }

    func testActivityIsIndependentOfGroupAndSubtitlesOnlyAppearInTooltips() {
        _ = NSApplication.shared
        let panel = DisplayPanelController()
        let entry = DisplayMenuEntry(
            id: 49, selectionID: nil, name: "iPad", isActive: false, isConnected: false,
            isControlledOffline: true, group: .open, sidecarDeviceID: "test-ipad",
            detailOverride: "随航 · 实验性 · 连接超时"
        )
        panel.update(entries: [entry], builtInActive: true, automatic: true, login: false, available: true)
        let views = descendants(panel.view)
        let activityIDs = views.compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("display-activity-") }
        XCTAssertEqual(activityIDs, ["display-activity-active", "display-activity-inactive"])
        XCTAssertEqual(views.filter { $0.accessibilityIdentifier() == "sidecar-badge" }.count, 1)
        let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertFalse(labels.contains { $0.contains("固定归属") || $0.contains("正在显示") || $0.contains("连接超时") || $0.contains("随航") })
        let row = views.compactMap { $0 as? DisplayGroupRow }.last
        XCTAssertTrue(row?.toolTip?.contains("连接超时") == true)
    }

    func testPickerAppearanceChangesKeepSelectionAndAccessibleState() {
        _ = NSApplication.shared
        let picker = DisplayGroupPicker(group: .unmanaged, fixed: false, enabled: true, deviceName: "Monitor")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            picker.appearance = NSAppearance(named: name)
            picker.viewDidChangeEffectiveAppearance()
            XCTAssertEqual(picker.selectedGroup, .unmanaged)
            XCTAssertNotNil(picker.layer?.backgroundColor)
            XCTAssertEqual(picker.buttons.last?.accessibilityValue() as? Int, 1)
            XCTAssertEqual(picker.buttons.first?.accessibilityValue() as? Int, 0)
        }
    }

    func testInsufficientScreensShowPausedSwitchButStillAllowGroupEditing() {
        _ = NSApplication.shared
        let panel = DisplayPanelController()
        let entry = DisplayMenuEntry(id: 3, selectionID: nil, name: "Offline", isActive: false, isConnected: false, isControlledOffline: false, group: .closed)
        panel.update(entries: [entry], builtInActive: true, automatic: true, login: false, available: true, switchingAllowed: false)
        let views = descendants(panel.view)
        let toggle = views.compactMap { $0 as? NSSwitch }.first { $0.accessibilityLabel() == "随开合盖切换" }
        XCTAssertEqual(toggle?.state, .off)
        XCTAssertFalse(toggle?.isEnabled == true)
        XCTAssertTrue(toggle?.toolTip?.contains("自动恢复") == true)
        XCTAssertTrue(views.compactMap { $0 as? DisplayGroupPicker }.last?.isEnabled == true)
        XCTAssertEqual(views.filter { $0.accessibilityIdentifier() == "built-in-lock" }.count, 1)
    }
}
