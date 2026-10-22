import AppKit
import Foundation
import LidSwitchCore

@MainActor
enum Diagnostics {
    static func run(verifyActiveEnable: Bool) -> Int32 {
        let controller = DisplayController()
        guard controller.isAvailable else {
            fputs("private-api: unavailable\n", stderr)
            return 1
        }

        do {
            let snapshot = try controller.snapshot(lid: LidStateReader.read())
            let namePairs: [(UInt32, String)] = NSScreen.screens.compactMap { screen in
                let key = NSDeviceDescriptionKey("NSScreenNumber")
                guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
                return (number.uint32Value, screen.localizedName)
            }
            let namesByID = Dictionary(uniqueKeysWithValues: namePairs)
            print("private-api: available")
            print("lid: \(snapshot.lid.rawValue)")
            let physicalCount = controller.connectedPhysicalDisplayCount()
            print("physical-connection-hints: \(physicalCount)")
            if let data = UserDefaults.standard.persistentDomain(forName: "local.chiu.LidSwitch")?["participatingExternalDisplays"] as? Data,
               let selections = try? JSONDecoder().decode([ExternalDisplaySelection].self, from: data) {
                for selection in selections {
                    print("group=\(selection.group.rawValue) last-display-id=\(selection.lastDisplayID) sidecar=\(selection.isSidecar) name=\(selection.name)")
                }
            }
            let sidecar = SidecarBridge()
            print("sidecar-api: \(sidecar.isAvailable ? "available" : "unavailable")")
            if let devices = try? sidecar.devices() {
                for device in devices {
                    print("sidecar-device=\(device.identifier) connected=\(device.isConnected) name=\(device.name)")
                }
            }
            print("displays: \(snapshot.displays.count)")
            for display in snapshot.displays {
                let name = display.isBuiltIn
                    ? "MacBook built-in display"
                    : namesByID[display.id, default: "unknown"]
                let selectable = display.isBuiltIn || display.isActive || display.isOnline
                print(
                    "id=\(display.id) builtin=\(display.isBuiltIn) " +
                    "active=\(display.isActive) online=\(display.isOnline) " +
                    "main=\(display.isMain) vendor=\(display.vendor) " +
                    "model=\(display.model) serial=\(display.serial) " +
                    "selectable=\(selectable) name=\(name)"
                )
            }

            if verifyActiveEnable {
                let activeIDs = snapshot.displays.filter { $0.isActive && !$0.isSidecar }.map(\.id)
                guard !activeIDs.isEmpty else {
                    fputs("verify-active-enable: no active display\n", stderr)
                    return 2
                }
                try controller.setEnabled(true, displayIDs: activeIDs)
                print("verify-active-enable: passed for \(activeIDs)")
            }
            return 0
        } catch {
            fputs("diagnostic-error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
