import Foundation
import LidSwitchCore
import OSLog

@MainActor
final class SidecarSessionController {
    private struct Target: Equatable {
        let identifier: String
        let goal: SidecarGoal
        let automatic: Bool
    }

    let client: SidecarClient
    var canPerformAutomatic: ((SidecarGoal) -> Bool)?
    var onChange: (() -> Void)?
    var onStatus: ((String) -> Void)?

    private let logger = Logger(subsystem: "local.chiu.LidSwitch", category: "sidecar")
    private let settleDelay: TimeInterval
    private let retryDelay: TimeInterval
    private let operationTimeout: TimeInterval
    private var target: Target?
    private var pending: DispatchWorkItem?
    private var operationID: UUID?
    private var timeout: DispatchWorkItem?
    private var retryBudget = SidecarRetryBudget()
    private(set) var disconnectedByApp: Set<String> = []
    private var detailByID: [String: String] = [:]

    var hasOutstandingRecovery: Bool { !disconnectedByApp.isEmpty || operationID != nil }

    init(
        client: SidecarClient,
        settleDelay: TimeInterval = 2.5,
        retryDelay: TimeInterval = 2,
        operationTimeout: TimeInterval = 15
    ) {
        self.client = client
        self.settleDelay = settleDelay
        self.retryDelay = retryDelay
        self.operationTimeout = operationTimeout
    }

    func setAutomaticGoal(_ goal: SidecarGoal, identifier: String) {
        setTarget(Target(identifier: identifier, goal: goal, automatic: true))
    }

    func pauseAutomatic() {
        guard target?.automatic == true else { return }
        suspend()
    }

    func suspend() {
        pending?.cancel()
        pending = nil
        target = nil
    }

    func restore() {
        if let id = disconnectedByApp.first {
            setTarget(Target(identifier: id, goal: .connect, automatic: false))
        } else {
            pending?.cancel()
            pending = nil
            target = nil
        }
    }

    func release(identifier: String) {
        if disconnectedByApp.contains(identifier) {
            setTarget(Target(identifier: identifier, goal: .connect, automatic: false))
        } else if target?.identifier == identifier {
            pending?.cancel()
            pending = nil
            target = nil
        }
    }

    func resetRetries() {
        retryBudget = SidecarRetryBudget()
    }

    func detail(for device: SidecarDeviceInfo) -> String {
        if let detail = detailByID[device.identifier] { return "随航 · 实验性 · \(detail)" }
        if disconnectedByApp.contains(device.identifier) && !device.isConnected {
            return "随航 · 实验性 · 已按分组断开"
        }
        return device.isConnected ? "随航 · 实验性 · 正在显示" : "随航 · 实验性 · 未连接"
    }

    private func setTarget(_ next: Target) {
        if target != next {
            pending?.cancel()
            pending = nil
            target = next
            let context = "\(next.identifier):\(next.goal):\(next.automatic)"
            let changedContext = retryBudget.context != context
            retryBudget.update(context: context)
            if changedContext { detailByID[next.identifier] = nil }
        }
        advance(after: next.goal == .connect ? settleDelay : 0)
    }

    private func advance(after delay: TimeInterval) {
        guard target != nil, pending == nil, operationID == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.performIfNeeded()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func performIfNeeded() {
        guard let current = target, operationID == nil else { return }
        // Recheck the live lid/display state immediately before touching the
        // session; a lid change can arrive while a connection is delayed.
        if current.automatic && canPerformAutomatic?(current.goal) != true { return }
        do {
            let device = try client.devices().first { $0.identifier == current.identifier }
            let connected = device?.isConnected == true
            if connected == (current.goal == .connect) {
                detailByID[current.identifier] = nil
                if connected { disconnectedByApp.remove(current.identifier) }
                if !current.automatic { target = nil }
                onChange?()
                return
            }
            guard retryBudget.beginAttempt() else {
                finishFailure(SidecarError.deviceUnavailable, for: current)
                return
            }
            guard device != nil else {
                finishFailure(SidecarError.deviceUnavailable, for: current)
                return
            }

            let id = UUID()
            operationID = id
            if current.goal == .disconnect { disconnectedByApp.insert(current.identifier) }
            detailByID[current.identifier] = current.goal == .connect ? "正在连接…" : "正在断开…"
            logger.info("Sidecar \(current.goal == .connect ? "connect" : "disconnect", privacy: .public), attempt \(self.retryBudget.attempts)")
            onChange?()

            let deadline = DispatchWorkItem { [weak self] in
                guard let self, self.operationID == id else { return }
                // The OS request cannot be cancelled. Keep it in flight after
                // a timeout instead of issuing a conflicting second request.
                self.detailByID[current.identifier] = "操作超时，请确认 iPad 已解锁"
                self.onStatus?(SidecarError.timeout.localizedDescription)
                self.logger.error("Sidecar operation timed out; waiting for outstanding OS callback")
                self.onChange?()
            }
            timeout = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + operationTimeout, execute: deadline)
            do {
                try client.setConnected(current.goal == .connect, identifier: current.identifier) { [weak self] error in
                    guard let self, self.operationID == id else { return }
                    self.timeout?.cancel()
                    self.timeout = nil
                    self.operationID = nil
                    guard self.target == current else {
                        self.advance(after: self.retryDelay)
                        return
                    }
                    if let error {
                        self.finishFailure(error, for: current)
                    } else {
                        self.detailByID[current.identifier] = nil
                        if current.goal == .connect { self.disconnectedByApp.remove(current.identifier) }
                        self.logger.info("Sidecar session request completed")
                        // Verify the resulting session rather than trusting a
                        // successful submission before it becomes observable.
                        self.advance(after: self.retryDelay)
                        self.onChange?()
                    }
                }
            } catch {
                timeout?.cancel()
                timeout = nil
                operationID = nil
                finishFailure(error, for: current)
            }
        } catch {
            detailByID[current.identifier] = "随航接口不可用"
            onStatus?(error.localizedDescription)
            onChange?()
        }
    }

    private func finishFailure(_ error: Error, for current: Target) {
        guard target == current else { return }
        let exhausted = retryBudget.attempts >= retryBudget.limit
        detailByID[current.identifier] = exhausted ? "切换未完成，请解锁后重新分组" : "正在重试…"
        logger.error("Sidecar request failed: \(error.localizedDescription, privacy: .public)")
        onStatus?("随航\(exhausted ? "已停止重试" : "正在重试")：\(error.localizedDescription)")
        onChange?()
        if !exhausted { advance(after: retryDelay * Double(max(1, retryBudget.attempts))) }
    }
}
