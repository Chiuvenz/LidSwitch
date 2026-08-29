import CLidSwitch
import Foundation
import LidSwitchCore

enum DisplayControllerError: LocalizedError {
    case privateAPIUnavailable
    case operationFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .privateAPIUnavailable:
            return "当前 macOS 没有提供 LidSwitch 所需的 SkyLight 接口"
        case .operationFailed(let code):
            if code == LS_ERROR_WOULD_DISABLE_LAST_DISPLAY {
                return "安全检查阻止了关闭最后一个活动显示器"
            }
            return "显示器操作失败（错误码 \(code)）"
        }
    }
}

final class DisplayController {
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

    func restoreAll(lid: LidState) throws {
        let state = try snapshot(lid: lid)
        var ids = state.externalDisplays.map(\.id)
        if lid != .closed, let builtIn = state.builtIn {
            ids.append(builtIn.id)
        }
        try setEnabled(true, displayIDs: Array(Set(ids)).sorted())
    }
}
