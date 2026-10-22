import Foundation
import XCTest
@testable import LidSwitchCore

final class SidecarPolicyTests: XCTestCase {
    func testWaitsForUsableScreenAndDoesNotSupportHeadlessReconnect() {
        let policy = SidecarPolicy()
        XCTAssertNil(policy.goal(lid: .open, builtInActive: false, externalActive: true))
        XCTAssertEqual(policy.goal(lid: .open, builtInActive: true, externalActive: false), .disconnect)
        XCTAssertNil(policy.goal(lid: .closed, builtInActive: true, externalActive: false))
        XCTAssertEqual(policy.goal(lid: .closed, builtInActive: false, externalActive: true), .connect)
        XCTAssertNil(policy.goal(lid: .unknown, builtInActive: true, externalActive: true))
    }

    func testDuplicateNotificationsDoNotResetRetryBudget() {
        var budget = SidecarRetryBudget()
        for _ in 0..<3 {
            budget.update(context: "same-device:connect")
            XCTAssertTrue(budget.beginAttempt())
        }
        budget.update(context: "same-device:connect")
        XCTAssertFalse(budget.beginAttempt())
        budget.update(context: "same-device:disconnect")
        XCTAssertTrue(budget.beginAttempt())
        XCTAssertEqual(budget.attempts, 1)
    }

    func testDeviceIdentityAndLegacySelectionRoundTrip() throws {
        let id = "12345678-1234-4ABC-8DEF-1234567890AB"
        XCTAssertEqual(SidecarIdentity.displaySerial(for: id), 0x12345678)
        XCTAssertNil(SidecarIdentity.displaySerial(for: "12345678-invalid"))
        let selected = ExternalDisplaySelection(sidecarDeviceID: id, name: "iPad")
        XCTAssertTrue(selected.isSidecar)
        XCTAssertEqual(try JSONDecoder().decode(ExternalDisplaySelection.self, from: JSONEncoder().encode(selected)), selected)
        let legacy = Data(#"{"vendor":1633775724,"model":1766875492,"serial":305419896,"lastDisplayID":49,"name":"Sidecar Display"}"#.utf8)
        let old = try JSONDecoder().decode(ExternalDisplaySelection.self, from: legacy)
        XCTAssertTrue(old.isSidecar)
        XCTAssertNil(old.sidecarDeviceID)
    }

    func testSidecarNeverEntersPhysicalDisplayTransaction() {
        let builtin = DisplayRecord(id: 1, vendor: 1, model: 1, serial: 0, isBuiltIn: true, isActive: true, isOnline: true, isMain: true)
        let ipad = DisplayRecord(id: 49, vendor: 1633775724, model: 1766875492, serial: 42, isBuiltIn: false, isActive: true, isOnline: true, isMain: false)
        let step = ReconciliationPlanner().nextStep(for: DisplaySnapshot(lid: .open, displays: [builtin, ipad]), selectedExternalIDs: [49])
        guard case .stable = step else { return XCTFail("Sidecar must not be disabled through SkyLight: \(step)") }
    }
}
