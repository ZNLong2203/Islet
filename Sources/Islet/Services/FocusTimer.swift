import AppKit

/// A Pomodoro-style countdown that shows up as a live activity beside the notch.
@Observable @MainActor
final class FocusTimer {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?

    /// Running, or paused part-way through.
    var isActive: Bool { isRunning || remaining < duration }
    var progress: Double { duration > 0 ? 1 - remaining / duration : 0 }

    var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func set(minutes: Int) {
        stopTicker()
        isRunning = false
        duration = TimeInterval(minutes * 60)
        remaining = duration
    }

    func start() {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = duration }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        // One wake-up per second, landing exactly when the displayed second changes.
        let fraction = remaining.truncatingRemainder(dividingBy: 1)
        let firstFire = Date().addingTimeInterval(fraction > 0.01 ? fraction : 1)
        let ticker = Timer(fire: firstFire, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.tolerance = 0.05
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func pause() {
        tick()
        stopTicker()
        isRunning = false
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        stopTicker()
        isRunning = false
        remaining = duration
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicker()
            isRunning = false
            remaining = duration
            NSSound(named: "Glass")?.play()
            onFinish?()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }
}
