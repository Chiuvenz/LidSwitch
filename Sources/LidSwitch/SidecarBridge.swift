import Foundation
import ObjectiveC
import Darwin

struct SidecarDeviceInfo: Equatable {
    let identifier: String
    let name: String
    let isConnected: Bool
}

enum SidecarError: LocalizedError {
    case unavailable
    case deviceUnavailable
    case timeout
    case tooManyDevices

    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前系统的随航接口不可用"
        case .deviceUnavailable: return "iPad 当前不可连接，请确认已唤醒并解锁"
        case .timeout: return "随航连接超时，请确认 iPad 已唤醒并解锁"
        case .tooManyDevices: return "实验性随航切换暂时只支持一台 iPad 参与分组"
        }
    }
}

@MainActor
protocol SidecarClient: AnyObject {
    var isAvailable: Bool { get }
    func devices() throws -> [SidecarDeviceInfo]
    func setConnected(_ connected: Bool, identifier: String, completion: @escaping (Error?) -> Void) throws
}

@MainActor
final class SidecarBridge: SidecarClient {
    private let manager: NSObject?

    init() {
        // Keep the framework loaded for the process lifetime: its asynchronous
        // callbacks may outlive an individual bridge instance.
        guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY | RTLD_LOCAL) != nil,
              let type = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              type.responds(to: NSSelectorFromString("sharedManager")),
              let instance = type.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject,
              ["devices", "connectedDevices", "connectToDevice:completion:", "disconnectFromDevice:completion:"].allSatisfy({
                  instance.responds(to: NSSelectorFromString($0))
              }) else {
            manager = nil
            return
        }
        manager = instance
    }

    var isAvailable: Bool { manager != nil }

    func devices() throws -> [SidecarDeviceInfo] {
        guard let manager else { throw SidecarError.unavailable }
        let connected = objects(manager, selector: "connectedDevices")
        let connectedIDs = Set(connected.compactMap(identifier))
        var seen: Set<String> = []
        return (connected + objects(manager, selector: "devices")).compactMap { device in
            guard let id = identifier(device), seen.insert(id).inserted else { return nil }
            let name = device.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String ?? "iPad"
            return SidecarDeviceInfo(identifier: id, name: name, isConnected: connectedIDs.contains(id))
        }
    }

    func setConnected(_ connected: Bool, identifier id: String, completion: @escaping (Error?) -> Void) throws {
        guard let manager else { throw SidecarError.unavailable }
        let candidates = objects(manager, selector: "connectedDevices") + objects(manager, selector: "devices")
        guard let device = candidates.first(where: { identifier($0) == id }) else {
            throw SidecarError.deviceUnavailable
        }
        let selector = NSSelectorFromString(connected ? "connectToDevice:completion:" : "disconnectFromDevice:completion:")
        typealias Callback = @convention(block) (NSError?) -> Void
        typealias Invoke = @convention(c) (AnyObject, Selector, AnyObject, Callback) -> Void
        let callback: Callback = { error in
            DispatchQueue.main.async { completion(error) }
        }
        let invoke = unsafeBitCast(manager.method(for: selector), to: Invoke.self)
        invoke(manager, selector, device, callback)
    }

    private func objects(_ manager: NSObject, selector: String) -> [NSObject] {
        manager.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? [NSObject] ?? []
    }

    private func identifier(_ device: NSObject) -> String? {
        guard device.responds(to: NSSelectorFromString("identifier")),
              let value = device.perform(NSSelectorFromString("identifier"))?.takeUnretainedValue(),
              let uuid = UUID(uuidString: String(describing: value)) else { return nil }
        return uuid.uuidString
    }
}
