import Foundation
import LidSwitchCore

enum Diagnostics {
    static func run(verifyActiveEnable: Bool) -> Int32 {
        let controller = DisplayController()
        guard controller.isAvailable else {
            fputs("private-api: unavailable\n", stderr)
            return 1
        }

        do {
            let snapshot = try controller.snapshot(lid: LidStateReader.read())
            print("private-api: available")
            print("lid: \(snapshot.lid.rawValue)")
            print("displays: \(snapshot.displays.count)")
            for display in snapshot.displays {
                print(
                    "id=\(display.id) builtin=\(display.isBuiltIn) " +
                    "active=\(display.isActive) online=\(display.isOnline) " +
                    "main=\(display.isMain) vendor=\(display.vendor) " +
                    "model=\(display.model)"
                )
            }

            if verifyActiveEnable {
                let activeIDs = snapshot.displays.filter(\.isActive).map(\.id)
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
