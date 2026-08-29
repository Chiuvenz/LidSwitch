import Foundation
import LidSwitchCore
import OSLog

@MainActor
final class SwitchCoordinator {
    private let controller: DisplayController
    private let planner = ReconciliationPlanner()
    private let logger = Logger(subsystem: "local.chiu.LidSwitch", category: "switch")
    private var generation = 0

    var onStatusChange: ((String) -> Void)?

    init(controller: DisplayController) {
        self.controller = controller
    }

    func reconcile(trigger: String, automatic: Bool) {
        generation += 1
        let currentGeneration = generation
        logger.info("Reconcile: \(trigger, privacy: .public)")
        runStep(generation: currentGeneration, attempt: 0, automatic: automatic)
    }

    func restoreAll() {
        generation += 1
        do {
            try controller.restoreAll(lid: LidStateReader.read())
            onStatusChange?("已请求恢复所有显示器")
        } catch {
            onStatusChange?("恢复失败：\(error.localizedDescription)")
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func currentStatus() -> String {
        do {
            return describe(try controller.snapshot(lid: LidStateReader.read()))
        } catch {
            return "状态不可用：\(error.localizedDescription)"
        }
    }

    private func runStep(generation: Int, attempt: Int, automatic: Bool) {
        guard generation == self.generation else { return }
        guard attempt < 16 else {
            onStatusChange?("切换超时；已停止重试，可选择“恢复所有显示器”")
            return
        }

        do {
            let snapshot = try controller.snapshot(lid: LidStateReader.read())
            onStatusChange?(describe(snapshot))
            let step = planner.nextStep(for: snapshot)

            guard automatic else { return }
            switch step {
            case .enable(let ids, let reason):
                logger.info("\(reason, privacy: .public): \(ids.description, privacy: .public)")
                try controller.setEnabled(true, displayIDs: ids)
                scheduleNext(generation: generation, attempt: attempt + 1)

            case .disable(let ids, let reason):
                logger.info("\(reason, privacy: .public): \(ids.description, privacy: .public)")
                try controller.setEnabled(false, displayIDs: ids)
                scheduleNext(generation: generation, attempt: attempt + 1)

            case .stable(let reason):
                onStatusChange?("\(describe(snapshot)) · \(reason)")

            case .blocked(let reason):
                onStatusChange?("已暂停：\(reason)")
                logger.error("Reconciliation blocked: \(reason, privacy: .public)")
            }
        } catch {
            onStatusChange?("切换失败：\(error.localizedDescription)")
            logger.error("Reconciliation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleNext(generation: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.runStep(generation: generation, attempt: attempt, automatic: true)
        }
    }

    private func describe(_ snapshot: DisplaySnapshot) -> String {
        let lidText: String
        switch snapshot.lid {
        case .open: lidText = "开盖"
        case .closed: lidText = "合盖"
        case .unknown: lidText = "盖子状态未知"
        }
        let externals = snapshot.externalDisplays
        let activeExternals = externals.filter(\.isActive).count
        let builtInText = snapshot.builtIn?.isActive == true ? "内屏开" : "内屏关"
        return "\(lidText) · \(builtInText) · 外屏 \(activeExternals)/\(externals.count) 开"
    }
}
