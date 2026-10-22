import CLidSwitch
import CoreGraphics
import Foundation
import LidSwitchCore

enum DisplayControllerError: LocalizedError {
    case privateAPIUnavailable
    case displayUnavailable
    case sidecarRequiresSession
    case operationFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .privateAPIUnavailable:
            return "当前 macOS 没有提供 LidSwitch 所需的 SkyLight 接口"
        case .displayUnavailable:
            return "所选显示器已断开或暂时不可用"
        case .sidecarRequiresSession:
            return "随航显示器必须通过会话管理，不能直接修改显示器拓扑"
        case .operationFailed(let code):
            if code == LS_ERROR_WOULD_DISABLE_LAST_DISPLAY {
                return "安全检查阻止了关闭最后一个活动显示器"
            }
            return "显示器操作失败（错误码 \(code)）"
        }
    }

    var isRetryable: Bool {
        guard case .operationFailed(let code) = self else { return false }
        // CoreGraphics reports transient display-server contention as either
        // kCGErrorFailure or kCGErrorCannotComplete.
        return code == 1000 || code == 1004
    }
}

@MainActor
protocol DisplayControlling {
    var isAvailable: Bool { get }
    func snapshot(lid: LidState) throws -> DisplaySnapshot
    func setEnabled(_ enabled: Bool, displayIDs: [UInt32]) throws
    func restore(lid: LidState, externalIDs: Set<UInt32>) throws
    func connectedPhysicalDisplayCount() -> Int
}

final class DisplayController: DisplayControlling {
    func connectedPhysicalDisplayCount() -> Int { PhysicalDisplayProbe.connectedCount() }
    var isAvailable: Bool {
        LSPrivateAPIStatus() == 0
    }

    func snapshot(lid: LidState) throws -> DisplaySnapshot {
        var buffer = Array(repeating: LSDisplayInfo(), count: 64)
        var count: UInt32 = 0
        let result = LSGetDisplays(&buffer, UInt32(buffer.count), &count)
        guard result == 0 else {
            if result == LS_ERROR_PRIVATE_API_UNAVAILABLE {
                throw DisplayControllerError.privateAPIUnavailable
            }
            throw DisplayControllerError.operationFailed(code: result)
        }

        let displays = buffer.prefix(Int(count)).map { info in
            DisplayRecord(
                id: info.displayID,
                vendor: info.vendor,
                model: info.model,
                serial: info.serial,
                isBuiltIn: info.isBuiltIn != 0,
                isActive: info.isActive != 0,
                isOnline: info.isOnline != 0,
                isMain: info.isMain != 0
            )
        }
        return DisplaySnapshot(lid: lid, displays: displays)
    }

    func setEnabled(_ enabled: Bool, displayIDs: [UInt32]) throws {
        guard !displayIDs.isEmpty else { return }
        guard !displayIDs.contains(where: {
            CGDisplayVendorNumber($0) == SidecarIdentity.displayVendor && CGDisplayModelNumber($0) == SidecarIdentity.displayModel
        }) else { throw DisplayControllerError.sidecarRequiresSession }
        var ids = displayIDs
        let result = ids.withUnsafeMutableBufferPointer { pointer in
            LSSetDisplaysEnabled(
                pointer.baseAddress,
                UInt32(pointer.count),
                enabled ? 1 : 0
            )
        }
        guard result == 0 else {
            if result == LS_ERROR_PRIVATE_API_UNAVAILABLE {
                throw DisplayControllerError.privateAPIUnavailable
            }
            throw DisplayControllerError.operationFailed(code: result)
        }
    }

    func restore(lid: LidState, externalIDs: Set<UInt32>) throws {
        let state = try snapshot(lid: lid)
        let knownExternalIDs = Set(state.externalDisplays.filter { !$0.isSidecar }.map(\.id))
        var ids = Array(externalIDs.intersection(knownExternalIDs))
        if lid != .closed, let builtIn = state.builtIn {
            ids.append(builtIn.id)
        }
        try setEnabled(true, displayIDs: Array(Set(ids)).sorted())
    }
}
