import CoreGraphics
import Foundation

private func displayConfigurationChanged(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context, !flags.contains(.beginConfigurationFlag) else { return }
    let observer = Unmanaged<DisplayChangeObserver>.fromOpaque(context).takeUnretainedValue()
    observer.notify()
}

final class DisplayChangeObserver {
    private let onChange: () -> Void
    private var registered = false
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func start() {
        registered = CGDisplayRegisterReconfigurationCallback(displayConfigurationChanged, Unmanaged.passUnretained(self).toOpaque()) == .success
    }
    func notify() { DispatchQueue.main.async { [weak self] in self?.onChange() } }
    func stop() {
        if registered {
            CGDisplayRemoveReconfigurationCallback(displayConfigurationChanged, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
    }
    deinit { stop() }
}
