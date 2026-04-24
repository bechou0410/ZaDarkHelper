import Foundation

/// Fires periodic checks for ZaDark formula updates.
/// Dispatch timer fires every `interval` seconds + once on start + on wake (wired externally).
final class UpdateScheduler: @unchecked Sendable {

    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "zadark.scheduler")
    private var timer: DispatchSourceTimer?
    private let onTick: @Sendable () -> Void

    init(interval: TimeInterval = 6 * 60 * 60, onTick: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: interval, leeway: .seconds(60))
        t.setEventHandler { [weak self] in self?.onTick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func fireNow() {
        queue.async { [weak self] in self?.onTick() }
    }
}
