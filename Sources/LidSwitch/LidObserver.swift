import Foundation
import IOKit
import LidSwitchCore

enum LidStateReader {
    static func read() -> LidState {
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            return .unknown
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return .unknown
        }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return .unknown
        }
        return value ? .closed : .open
    }
}

private func lidInterestCallback(
    refcon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: natural_t,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let observer = Unmanaged<LidObserver>.fromOpaque(refcon).takeUnretainedValue()
    observer.handleKernelNotification()
}

final class LidObserver {
    private var service: io_service_t = IO_OBJECT_NULL
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var lastState: LidState = .unknown
    private let onChange: (LidState) -> Void

    init(onChange: @escaping (LidState) -> Void) {
        self.onChange = onChange
    }

    @discardableResult
    func start() -> Bool {
        guard notificationPort == nil,
              let matching = IOServiceMatching("IOPMrootDomain") else {
            return false
        }

        service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL,
              let port = IONotificationPortCreate(kIOMainPortDefault) else {
            stop()
            return false
        }
        notificationPort = port

        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            lidInterestCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )
        guard result == KERN_SUCCESS else {
            stop()
            return false
        }

        lastState = LidStateReader.read()
        return true
    }

    func handleKernelNotification() {
        let current = LidStateReader.read()
        guard current != lastState else { return }
        lastState = current
        onChange(current)
    }

    func stop() {
        if notifier != IO_OBJECT_NULL {
            IOObjectRelease(notifier)
            notifier = IO_OBJECT_NULL
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            service = IO_OBJECT_NULL
        }
    }

    deinit {
        stop()
    }
}
