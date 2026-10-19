import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = DisplayController()
    private lazy var coordinator = SwitchCoordinator(controller: controller)
    private var lidObserver: LidObserver?
    private var screenObserver: NSObjectProtocol?
    private var screenReconcileWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "正在读取状态…", action: nil, keyEquivalent: "")
    private let automaticMenuItem = NSMenuItem(title: "自动切换", action: #selector(toggleAutomatic), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")

    private var automaticEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "automaticEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "automaticEnabled")
            automaticMenuItem.state = newValue ? .on : .off
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()

        coordinator.onStatusChange = { [weak self] status in
            self?.statusMenuItem.title = "状态：\(status)"
        }

        guard controller.isAvailable else {
            statusMenuItem.title = "状态：当前系统接口不可用"
            automaticMenuItem.isEnabled = false
            return
        }

        let observer = LidObserver { [weak self] state in
            guard let self else { return }
            self.screenReconcileWorkItem?.cancel()
            self.coordinator.reconcile(
                trigger: state == .closed ? "检测到合盖" : "检测到开盖",
                automatic: self.automaticEnabled
            )
        }
        lidObserver = observer
        if !observer.start() {
            statusMenuItem.title = "状态：无法监听开合盖事件"
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleScreenReconciliation()
            }
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceNotifications.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.coordinator.reconcile(
                        trigger: "系统即将睡眠",
                        automatic: self.automaticEnabled
                    )
                }
            }
        )
        workspaceObservers.append(
            workspaceNotifications.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.coordinator.reconcile(
                        trigger: "系统已经唤醒",
                        automatic: self.automaticEnabled
                    )
                }
            }
        )

        coordinator.reconcile(trigger: "应用启动", automatic: automaticEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenReconcileWorkItem?.cancel()
        coordinator.restoreAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceNotifications.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        lidObserver?.stop()
    }

    private func configureMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.2.swap",
            accessibilityDescription: "LidSwitch"
        )
        statusItem.button?.toolTip = "LidSwitch"

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        automaticMenuItem.target = self
        automaticMenuItem.state = automaticEnabled ? .on : .off
        menu.addItem(automaticMenuItem)

        let applyItem = NSMenuItem(
            title: "立即按当前开合盖状态切换",
            action: #selector(applyCurrentState),
            keyEquivalent: ""
        )
        applyItem.target = self
        menu.addItem(applyItem)

        let restoreItem = NSMenuItem(
            title: "恢复所有显示器",
            action: #selector(restoreAll),
            keyEquivalent: "r"
        )
        restoreItem.target = self
        menu.addItem(restoreItem)
        menu.addItem(.separator())

        loginMenuItem.target = self
        refreshLoginItemState()
        menu.addItem(loginMenuItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 LidSwitch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func scheduleScreenReconciliation() {
        screenReconcileWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.coordinator.reconcile(
                trigger: "显示器配置发生变化",
                automatic: self.automaticEnabled
            )
        }
        screenReconcileWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    @objc private func toggleAutomatic() {
        automaticEnabled.toggle()
        if automaticEnabled {
            coordinator.reconcile(trigger: "启用自动切换", automatic: true)
        } else {
            coordinator.restoreAll()
        }
    }

    @objc private func applyCurrentState() {
        coordinator.reconcile(trigger: "手动应用", automatic: true)
    }

    @objc private func restoreAll() {
        automaticEnabled = false
        coordinator.restoreAll()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refreshLoginItemState()
        } catch {
            showAlert(title: "无法更改登录启动设置", message: error.localizedDescription)
        }
    }

    private func refreshLoginItemState() {
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
