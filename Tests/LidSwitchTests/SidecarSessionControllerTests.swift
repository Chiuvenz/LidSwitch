import Foundation
import XCTest
import LidSwitchCore
@testable import LidSwitch

@MainActor
private final class FakeSidecarClient: SidecarClient {
    let isAvailable = true
    var connected = false
    var fail = false
    var autoComplete = true
    var calls: [Bool] = []
    var callbacks: [(Error?) -> Void] = []
    func devices() throws -> [SidecarDeviceInfo] {
        [SidecarDeviceInfo(identifier: "test-ipad", name: "iPad", isConnected: connected)]
    }
    func setConnected(_ value: Bool, identifier: String, completion: @escaping (Error?) -> Void) throws {
        calls.append(value)
        if autoComplete {
            if !fail { connected = value }
            completion(fail ? SidecarError.deviceUnavailable : nil)
        } else {
            callbacks.append(completion)
        }
    }
}

@MainActor
final class SidecarSessionControllerTests: XCTestCase {
    private func controller(_ client: FakeSidecarClient, settle: TimeInterval = 0.001, timeout: TimeInterval = 1) -> SidecarSessionController {
        let result = SidecarSessionController(client: client, settleDelay: settle, retryDelay: 0.002, operationTimeout: timeout)
        result.canPerformAutomatic = { _ in true }
        return result
    }
    private func tick(_ milliseconds: UInt64 = 80) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    func testConnectionAndOwnedDisconnectionRecovery() async {
        let client = FakeSidecarClient()
        client.connected = true
        let sut = controller(client)
        sut.setAutomaticGoal(.disconnect, identifier: "test-ipad")
        await tick()
        XCTAssertEqual(client.calls, [false])
        XCTAssertTrue(sut.disconnectedByApp.contains("test-ipad"))
        sut.restore()
        await tick()
        XCTAssertEqual(client.calls, [false, true])
        XCTAssertTrue(sut.disconnectedByApp.isEmpty)
    }

    func testRepeatedScreenNotificationsCannotCreateUnboundedRetries() async {
        let client = FakeSidecarClient()
        client.fail = true
        let sut = controller(client)
        sut.setAutomaticGoal(.connect, identifier: "test-ipad")
        await tick()
        for _ in 0..<5 {
            sut.pauseAutomatic()
            sut.setAutomaticGoal(.connect, identifier: "test-ipad")
            await tick(5)
        }
        XCTAssertEqual(client.calls, [true, true, true])
        sut.resetRetries()
        sut.setAutomaticGoal(.connect, identifier: "test-ipad")
        await tick()
        XCTAssertEqual(client.calls.count, 6)
    }

    func testOppositeRequestWaitsForOutstandingCallbackEvenAfterTimeout() async {
        let client = FakeSidecarClient()
        client.connected = true
        client.autoComplete = false
        let sut = controller(client, timeout: 0.01)
        sut.setAutomaticGoal(.disconnect, identifier: "test-ipad")
        await tick(30)
        sut.setAutomaticGoal(.connect, identifier: "test-ipad")
        await tick(30)
        XCTAssertEqual(client.calls, [false])
        client.connected = false
        client.callbacks.removeFirst()(nil)
        await tick(30)
        XCTAssertEqual(client.calls, [false, true])
        client.connected = true
        client.callbacks.removeFirst()(nil)
        await tick()
        XCTAssertTrue(sut.disconnectedByApp.isEmpty)
    }

    func testCancelledDelayedConnectAndLiveSafetyCheck() async {
        let client = FakeSidecarClient()
        let sut = controller(client, settle: 0.03)
        sut.setAutomaticGoal(.connect, identifier: "test-ipad")
        sut.pauseAutomatic()
        await tick()
        XCTAssertTrue(client.calls.isEmpty)
        sut.canPerformAutomatic = { _ in false }
        sut.setAutomaticGoal(.connect, identifier: "test-ipad")
        await tick()
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testUnselectedOrUnownedSessionIsNotRestored() async {
        let client = FakeSidecarClient()
        let sut = controller(client)
        sut.restore()
        sut.release(identifier: "test-ipad")
        await tick()
        XCTAssertTrue(client.calls.isEmpty)
    }
}
