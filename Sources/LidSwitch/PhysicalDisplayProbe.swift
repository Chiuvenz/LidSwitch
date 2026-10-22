import Foundation
import IOKit

enum PhysicalDisplayProbe {
    /// Apple Silicon's port hints remain present when SkyLight disables a
    /// connected display, but empty ports have an empty DisplayHints dictionary.
    /// Do not infer attachment from cached/offline CoreGraphics records.
    static func connectedCount() -> Int {
        guard let matching = IOServiceMatching("AppleDCPDPTXRemotePortUFP") else { return 0 }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var count = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            if let hints = IORegistryEntryCreateCFProperty(service, "DisplayHints" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let id = hints["EDID UUID"] as? String, UUID(uuidString: id) != nil {
                count += 1
            }
            IOObjectRelease(service)
        }
        return count
    }
}
