import BackgroundTasks
import Foundation

/// iOS 26's continued processing task: work the person started keeps running after Poki leaves the
/// screen, shown by iOS with its own progress UI, with no silent audio and no location. Poki holds one
/// while it is on and ends it when it turns off. iOS may end it early (under load, or when the person
/// stops it from that UI); then BackgroundKeeper falls back to silent audio.
@available(iOS 26.0, *)
@MainActor
final class ContinuedRun {
    private var task: BGContinuedProcessingTask?
    private var identifier: String?
    private var ticker: Task<Void, Never>?
    private var registered: Set<String> = []
    /// iOS ended the task before Poki turned off.
    var onExpired: (() -> Void)?
    private(set) var isRunning = false

    /// Asks iOS for the task; must be called while Poki is in front. False when iOS refuses.
    func begin(subtitle: String) -> Bool {
        guard !isRunning, let bundle = Bundle.main.bundleIdentifier else { return isRunning }
        let id = "\(bundle).run.\(UUID().uuidString.prefix(8).lowercased())"
        let wildcard = "\(bundle).run.*"
        if !registered.contains(wildcard) {
            let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: wildcard, using: .main) { [weak self] task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                MainActor.assumeIsolated { self?.started(task) }
            }
            if !ok { AppLog.shared.add("background", "continued run: iOS would not register \(wildcard)"); return false }
            registered.insert(wildcard)
        }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: String(localized: "Poki is on"), subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.shared.add("background", "continued run refused: \(error.localizedDescription)")
            return false
        }
        identifier = id
        isRunning = true
        AppLog.shared.add("background", "continued run requested (\(id))")
        return true
    }

    private func started(_ task: BGContinuedProcessingTask) {
        guard isRunning else { task.setTaskCompleted(success: true); return }
        self.task = task
        task.progress.totalUnitCount = 1_000
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                AppLog.shared.add("background", "continued run ended by iOS")
                self.finish(success: false)
                self.onExpired?()
            }
        }
        // iOS ends a task that shows no progress: a tick every few seconds, never reaching the end.
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, let task = self.task {
                let p = task.progress
                if p.completedUnitCount < p.totalUnitCount - 1 { p.completedUnitCount += 1 } else { p.completedUnitCount = p.totalUnitCount / 2 }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        AppLog.shared.add("background", "continued run started: Poki keeps running without silent audio")
    }

    func update(subtitle: String) {
        task?.updateTitle(String(localized: "Poki is on"), subtitle: subtitle)
    }

    func end() { finish(success: true) }

    private func finish(success: Bool) {
        isRunning = false
        ticker?.cancel(); ticker = nil
        if let task { task.progress.completedUnitCount = task.progress.totalUnitCount; task.setTaskCompleted(success: success) }
        task = nil
        if let identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        identifier = nil
    }
}
