import AppKit
import LidSwitchCore

@MainActor
final class DisplayPanelController: NSViewController {
    var onChangeGroup: ((DisplayMenuEntry, DisplayGroup) -> Void)?
    var onToggleAutomatic: ((Bool) -> Void)?
    var onToggleLogin: ((Bool) -> Void)?
    var onQuit: (() -> Void)?
    private let automaticSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let deviceStack = NSStackView()
    private let scrollView = NSScrollView()
    private var scrollHeight: NSLayoutConstraint!
    private let panelWidth: CGFloat = 480

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        view = background

        let content = stack(.vertical, spacing: 14)
        content.alignment = .leading
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            view.widthAnchor.constraint(equalToConstant: panelWidth)
        ])

        automaticSwitch.target = self
        automaticSwitch.action = #selector(toggleAutomatic)
        automaticSwitch.setAccessibilityLabel("随开合盖切换")
        let automaticLabel = label("随开合盖切换", size: 11)
        automaticLabel.textColor = .secondaryLabelColor
        content.addArrangedSubview(stack(.horizontal, views: [
            label("LidSwitch", size: 20, weight: .semibold),
            NSView(), automaticLabel, automaticSwitch
        ]))
        content.addArrangedSubview(separator())

        let caption = label("开盖或合盖，自动启用或停用屏幕", size: 12, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        content.addArrangedSubview(caption)

        deviceStack.orientation = .vertical
        deviceStack.alignment = .leading
        deviceStack.spacing = 4
        deviceStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = deviceStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([
            scrollHeight,
            deviceStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            deviceStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            deviceStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
        ])
        content.addArrangedSubview(scrollView)
        content.addArrangedSubview(separator())

        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        loginSwitch.controlSize = .small
        loginSwitch.setAccessibilityLabel("登录时启动")
        let quitButton = NSButton(title: "退出", target: self, action: #selector(quit))
        quitButton.bezelStyle = .inline
        quitButton.font = .systemFont(ofSize: 12)
        content.addArrangedSubview(stack(.horizontal, views: [
            quitButton, NSView(),
            stack(.horizontal, views: [label("登录时启动", size: 12), loginSwitch])
        ]))
        for child in content.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
    }

    func update(entries: [DisplayMenuEntry], builtInActive: Bool, automatic: Bool, login: Bool, available: Bool, switchingAllowed: Bool = true) {
        loadViewIfNeeded()
        automaticSwitch.state = automatic && switchingAllowed ? .on : .off
        automaticSwitch.isEnabled = available && switchingAllowed
        automaticSwitch.toolTip = switchingAllowed
            ? "根据 MacBook 开合盖，启用对应屏幕并停用另一状态的屏幕；“交给系统”的设备不受控制"
            : (automatic ? "可用屏幕不足，已暂停；连接外屏后自动恢复" : "至少连接一块额外屏幕后才能启用")
        automaticSwitch.setAccessibilityHelp(automaticSwitch.toolTip)
        loginSwitch.state = login ? .on : .off
        let focusedIdentifier = (view.window?.firstResponder as? NSView)?.identifier
        let previousOffset = scrollView.contentView.bounds.origin
        for child in deviceStack.arrangedSubviews {
            deviceStack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        addRow(DisplayGroupRow(
            name: "MacBook 内建显示器", detail: "固定归属 · 开盖时使用",
            symbol: "laptopcomputer", group: .open, active: builtInActive,
            fixed: true, sidecar: false, enabled: available
        ))
        let duplicateNames = Dictionary(grouping: entries, by: \.name)
        for entry in entries {
            var name = entry.name
            if (duplicateNames[entry.name]?.count ?? 0) > 1 {
                let suffix = entry.sidecarDeviceID.map { String($0.prefix(8)) } ?? String(entry.id)
                name += " · \(suffix)"
            }
            let detail: String
            if let override = entry.detailOverride {
                detail = override
            } else if entry.isControlledOffline {
                detail = "已按分组停用"
            } else if !entry.isConnected {
                detail = "未连接 · 分组已保留"
            } else if entry.group == .unmanaged {
                detail = "由 macOS 管理"
            } else {
                detail = entry.isActive ? "正在显示" : "已连接"
            }
            let row = DisplayGroupRow(
                name: name, detail: detail,
                symbol: entry.sidecarDeviceID == nil ? "display" : "ipad",
                group: entry.group, active: entry.isActive, fixed: false,
                sidecar: entry.sidecarDeviceID != nil, enabled: available
            )
            row.onChange = { [weak self] group in self?.onChangeGroup?(entry, group) }
            addRow(row)
        }
        if entries.isEmpty {
            let empty = label("连接外接显示器，选择何时显示", size: 12)
            empty.textColor = .tertiaryLabelColor
            empty.heightAnchor.constraint(equalToConstant: 30).isActive = true
            deviceStack.addArrangedSubview(empty)
        }
        scrollHeight.constant = min(CGFloat(1 + entries.count) * 58 - 4 + (entries.isEmpty ? 34 : 0), 336)
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: panelWidth, height: view.fittingSize.height)
        let maxOffset = max(0, deviceStack.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(previousOffset.y, maxOffset)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if let focusedIdentifier,
           let button = deviceStack.arrangedSubviews.compactMap({ $0 as? DisplayGroupRow })
                .flatMap({ $0.picker.buttons }).first(where: { $0.identifier == focusedIdentifier && $0.isEnabled }) {
            view.window?.makeFirstResponder(button)
        }
    }

    private func addRow(_ row: DisplayGroupRow) {
        deviceStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: deviceStack.widthAnchor).isActive = true
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }

    private func stack(_ orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat = 8, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.alignment = orientation == .horizontal ? .centerY : .leading
        stack.spacing = spacing
        return stack
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    @objc private func toggleAutomatic() { onToggleAutomatic?(automaticSwitch.state == .on) }
    @objc private func toggleLogin() { onToggleLogin?(loginSwitch.state == .on) }
    @objc private func quit() { onQuit?() }
}

/// Display activity is encoded by the device icon, never by group assignment.
@MainActor
final class DisplayGroupRow: NSView {
    var onChange: ((DisplayGroup) -> Void)?
    private let circle = NSView()
    private let icon: NSImageView
    private let active: Bool
    let picker: DisplayGroupPicker

    init(name: String, detail: String, symbol: String, group: DisplayGroup, active: Bool, fixed: Bool, sidecar: Bool, enabled: Bool) {
        self.active = active
        picker = DisplayGroupPicker(group: group, fixed: fixed, enabled: enabled, deviceName: name)
        icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        super.init(frame: .zero)
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 16
        circle.setAccessibilityElement(true)
        circle.setAccessibilityLabel("\(name)，\(active ? "正在显示" : "未显示")")
        circle.setAccessibilityIdentifier("display-activity-\(active ? "active" : "inactive")")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        circle.addSubview(icon)
        toolTip = "\(name) · \(active ? "正在显示" : "未显示")\n\(detail)"

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let nameGroup = NSStackView(views: [nameLabel])
        nameGroup.orientation = .horizontal
        nameGroup.alignment = .centerY
        nameGroup.spacing = 6
        if fixed || sidecar {
            let mark = NSImageView(image: NSImage(systemSymbolName: fixed ? "lock.fill" : "airplayvideo", accessibilityDescription: nil)!)
            mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: fixed ? 9 : 11, weight: .regular)
            mark.contentTintColor = .secondaryLabelColor
            mark.setAccessibilityElement(true)
            mark.setAccessibilityLabel(fixed ? "内建显示器仅在开盖时显示，无法更改" : "随航设备（实验性）")
            mark.setAccessibilityIdentifier(fixed ? "built-in-lock" : "sidecar-badge")
            mark.toolTip = fixed ? "内建显示器开盖时启用，合盖时由系统关闭，不可更改" : "随航 · 实验性"
            mark.widthAnchor.constraint(equalToConstant: 12).isActive = true
            mark.heightAnchor.constraint(equalToConstant: 12).isActive = true
            nameGroup.addArrangedSubview(mark)
        }
        picker.onChange = { [weak self] group in self?.onChange?(group) }
        [circle, nameGroup, picker].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 54),
            circle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            circle.centerYAnchor.constraint(equalTo: centerYAnchor),
            circle.widthAnchor.constraint(equalToConstant: 32),
            circle.heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            nameGroup.leadingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 10),
            nameGroup.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameGroup.trailingAnchor.constraint(lessThanOrEqualTo: picker.leadingAnchor, constant: -14),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            picker.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor = active ? .systemBlue : .secondaryLabelColor
            circle.layer?.backgroundColor = color.withAlphaComponent(0.11).cgColor
            icon.contentTintColor = color
        }
    }

}

/// A quiet capsule track with native buttons for focus, Space, and VoiceOver.
/// The built-in display uses the same control, with its assignment locked.
@MainActor
final class DisplayGroupPicker: NSView {
    var onChange: ((DisplayGroup) -> Void)?
    private(set) var selectedGroup: DisplayGroup
    let isFixed: Bool
    let isEnabled: Bool
    private(set) var buttons: [NSButton] = []

    init(group: DisplayGroup, fixed: Bool, enabled: Bool, deviceName: String) {
        selectedGroup = group
        isFixed = fixed
        isEnabled = enabled && !fixed
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 15
        setAccessibilityLabel("\(deviceName)何时显示")
        toolTip = fixed ? "内建显示器开盖时启用，合盖时由系统关闭，不可更改" : "选择这台显示器何时显示"
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, option) in DisplayGroup.allCases.enumerated() {
            let button = GroupChoiceButton(title: option.title, target: self, action: #selector(choose(_:)))
            button.tag = index
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.focusRingType = .exterior
            (button.cell as? NSButtonCell)?.highlightsBy = []
            (button.cell as? NSButtonCell)?.showsStateBy = []
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            button.isEnabled = isEnabled
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityLabel(option.title)
            button.setAccessibilityIdentifier("\(deviceName):\(option.rawValue)")
            button.identifier = NSUserInterfaceItemIdentifier("\(deviceName):\(option.rawValue)")
            button.toolTip = fixed ? toolTip : option.help
            button.setAccessibilityHelp(button.toolTip)
            button.onNavigate = { [weak self] offset in self?.navigate(from: index, offset: offset) }
            button.widthAnchor.constraint(equalToConstant: 64).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 196),
            heightAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.045)).cgColor
            for button in buttons {
                let selected = DisplayGroup.allCases[button.tag] == selectedGroup
                let color: NSColor = selected ? .labelColor : (isEnabled ? .secondaryLabelColor : .tertiaryLabelColor)
                button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: selected ? .medium : .regular),
                    .foregroundColor: color
                ])
                button.contentTintColor = .secondaryLabelColor
                button.layer?.backgroundColor = selected
                    ? (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.white.withAlphaComponent(0.95)).cgColor
                    : NSColor.clear.cgColor
                button.layer?.shadowColor = NSColor.black.cgColor
                button.layer?.shadowOpacity = selected ? (dark ? 0.16 : 0.08) : 0
                button.layer?.shadowRadius = 1.5
                button.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
                button.setAccessibilityValue(selected ? 1 : 0)
            }
        }
    }

    @objc private func choose(_ sender: NSButton) {
        guard isEnabled, DisplayGroup.allCases.indices.contains(sender.tag) else { return }
        let group = DisplayGroup.allCases[sender.tag]
        guard group != selectedGroup else { return }
        selectedGroup = group
        updateAppearance()
        onChange?(group)
    }

    private func navigate(from index: Int, offset: Int) {
        guard isEnabled else { return }
        let index = (index + offset + buttons.count) % buttons.count
        window?.makeFirstResponder(buttons[index])
        choose(buttons[index])
    }
}

@MainActor
private final class GroupChoiceButton: NSButton {
    var onNavigate: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 124 {
            onNavigate?(event.keyCode == 123 ? -1 : 1)
        } else {
            super.keyDown(with: event)
        }
    }
}
