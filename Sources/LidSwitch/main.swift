import AppKit
import Darwin

if CommandLine.arguments.contains("--diagnose") {
    exit(Diagnostics.run(verifyActiveEnable: false))
} else if CommandLine.arguments.contains("--verify-active-enable") {
    exit(Diagnostics.run(verifyActiveEnable: true))
} else {
    let application = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    application.delegate = delegate
    application.run()
}
