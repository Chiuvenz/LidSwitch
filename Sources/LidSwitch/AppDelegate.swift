import AppKit
import LidSwitchCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let selectionsKey = "participatingExternalDisplays"
    private static let legacySelectionKey = "selectedExternalDisplay"
    private let controller = DisplayController()
    private lazy var coordinator = SwitchCoordinator(controller: controller, selections: loadSelections())
    private let panel = DisplayPanelController()
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var lidObserver: LidObserver?
    private var screenObserver: NSObjectProtocol?
    private var displayObserver: DisplayChangeObserver?
    private var screenReconcileWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayNamesByID: [UInt32: String] = [:]
    private var preparedForTermination = false

    private var automaticEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "automaticEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "automaticEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePanel()
        coordinator.onStatusChange = { [weak self] status in
            self?.statusItem.button?.toolTip = "LidSwitch · \(status)"
        }
        coordinator.onSelectionChange = { [weak self] selections in
            self?.saveSelections(selections)
        }
        coordinator.onDisplayChange = { [weak self] in self?.refreshPanelIfShown() }
        guard controller.isAvailable else {
            statusItem.button?.toolTip = "当前系统的显示器切换接口不可用"
            refreshPanel()
            return
        }

        let observer = LidObserver { [weak self] state in
            guard let self else { return }
            self.screenReconcileWorkItem?.cancel()
            self.coordinator.reconcile(
                trigger: state == .closed ? "检测到合盖" : "检测到开盖",
                automatic: self.automaticEnabled
            )
            self.refreshPanelIfShown()
        }
        lidObserver = observer
        if !observer.start() { statusItem.button?.toolTip = "无法监听开合盖事件" }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPanelIfShown()
                self?.scheduleScreenReconciliation()
            }
        }
        let displayObserver = DisplayChangeObserver { [weak self] in self?.scheduleScreenReconciliation() }
        self.displayObserver = displayObserver
        displayObserver.start()
        let notifications = NSWorkspace.shared.notificationCenter
        // Reconcile after wake; submitting a new transaction while macOS is
        // tearing down displays for sleep can leave a stale session override.
        workspaceObservers.append(notifications.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleScreenReconciliation() }
        })
        workspaceObservers.append(notifications.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenReconcileWorkItem?.cancel()
                self?.coordinator.suspendForSleep()
            }
        })
        coordinator.reconcile(trigger: "应用启动", automatic: automaticEnabled)
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.async { [weak self] in self?.togglePanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenReconcileWorkItem?.cancel()
        if !preparedForTermination { coordinator.restoreManagedDisplays() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        let notifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { notifications.removeObserver($0) }
        lidObserver?.stop()
        displayObserver?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        preparedForTermination = true
        screenReconcileWorkItem?.cancel()
        lidObserver?.stop()
        displayObserver?.stop()
        coordinator.restoreManagedDisplays()
        guard coordinator.hasOutstandingRecovery else { return .terminateNow }
        // Sidecar recovery is asynchronous. Allow it a bounded grace period
        // without indefinitely delaying Quit or system shutdown.
        Task { @MainActor [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard self?.coordinator.hasOutstandingRecovery == true else { break }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configurePanel() {
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "LidSwitch")
        statusItem.button?.toolTip = "LidSwitch · 参与切换的显示器"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        popover.behavior = .transient
        popover.contentViewController = panel
        popover.animates = true
        panel.onChangeGroup = { [weak self] entry, group in
            guard let self else { return }
            do {
                self.screenReconcileWorkItem?.cancel()
                try self.coordinator.setGroup(group, for: entry)
                self.coordinator.reconcile(trigger: "更新显示器分组", automatic: self.automaticEnabled)
                self.refreshPanel()
            } catch {
                self.showError("无法更新显示器分组", error)
                self.coordinator.reconcile(trigger: "保留原显示器分组", automatic: self.automaticEnabled)
                self.refreshPanel()
            }
        }
        panel.onToggleAutomatic = { [weak self] enabled in
            guard let self else { return }
            self.screenReconcileWorkItem?.cancel()
            self.automaticEnabled = enabled
            if enabled {
                self.coordinator.reconcile(trigger: "启用自动切换", automatic: true)
            } else {
                self.coordinator.restoreManagedDisplays()
            }
            self.refreshPanel()
        }
        panel.onToggleLogin = { [weak self] enabled in
            guard let self else { return }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch { self.showError("无法更改登录启动设置", error) }
            self.refreshPanel()
        }
        panel.onQuit = { NSApp.terminate(nil) }
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        refreshPanel()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshPanelIfShown() {
        if popover.isShown { refreshPanel() }
    }

    private func refreshPanel() {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let id = screen.deviceDescription[key] as? NSNumber {
                displayNamesByID[id.uint32Value] = screen.localizedName
            }
        }
        do {
            let entries = try coordinator.displayMenuEntries(namesByID: displayNamesByID)
            panel.update(
                entries: entries,
                builtInActive: coordinator.builtInActive,
                automatic: automaticEnabled,
                login: SMAppService.mainApp.status == .enabled,
                available: controller.isAvailable,
                switchingAllowed: coordinator.switchingAllowed
            )
        } catch {
            statusItem.button?.toolTip = error.localizedDescription
            panel.update(entries: [], builtInActive: false, automatic: automaticEnabled,
                         login: SMAppService.mainApp.status == .enabled, available: false)
        }
        popover.contentSize = panel.preferredContentSize
    }

    private func scheduleScreenReconciliation() {
        guard !preparedForTermination else { return }
        screenReconcileWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.preparedForTermination else { return }
            self.coordinator.reconcile(trigger: "显示器配置发生变化", automatic: self.automaticEnabled)
            self.refreshPanelIfShown()
        }
        screenReconcileWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    private func loadSelections() -> [ExternalDisplaySelection] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.selectionsKey),
           let selections = try? JSONDecoder().decode([ExternalDisplaySelection].self, from: data) {
            saveSelections(selections)
            return selections
        }
        if let data = defaults.data(forKey: Self.legacySelectionKey),
           let selection = try? JSONDecoder().decode(ExternalDisplaySelection.self, from: data) {
            saveSelections([selection])
            return [selection]
        }
        return []
    }

    private func saveSelections(_ selections: [ExternalDisplaySelection]) {
        if let data = try? JSONEncoder().encode(selections) {
            UserDefaults.standard.set(data, forKey: Self.selectionsKey)
            UserDefaults.standard.removeObject(forKey: Self.legacySelectionKey)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        popover.performClose(nil)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
