import SwiftUI

enum ExpandedTab: String, CaseIterable, Identifiable {
    case home, notes, shelf, timer

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .notes: "note.text"
        case .shelf: "tray.full.fill"
        case .timer: "timer"
        }
    }
}

/// Short-lived notifications that pop out of the notch and retract on their own.
enum PeekKind: Equatable {
    case power(plugged: Bool)
    case lowBattery
    case timerFinished
    case nowPlaying
}

enum Presentation: Equatable {
    /// Same size as the physical notch: invisible.
    case idle
    /// Live activity: small content on both sides of the camera.
    case wings
    case peek(PeekKind)
    case expanded
}

@Observable @MainActor
final class IslandModel {
    var notchSize = CGSize(width: 185, height: 32)
    var isExpanded = false
    var tab: ExpandedTab = .home
    var isDropTargeted = false
    /// Bumped to ask the notes editor to grab keyboard focus.
    var notesFocusRequest = 0
    private(set) var peek: PeekKind?

    let media = NowPlayingService()
    let battery = BatteryService()
    let shelf = ShelfStore()
    let timer = FocusTimer()
    let calendar = CalendarService()
    let notes = NotesStore()

    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var launchDate = Date()

    var presentation: Presentation {
        if isExpanded { return .expanded }
        if let peek { return .peek(peek) }
        if media.showsActivity || timer.isActive { return .wings }
        return .idle
    }

    /// Wider wings when the timer needs room for its digits.
    var wingWidth: CGFloat { timer.isActive ? 54 : Metrics.wing }

    var topRadius: CGFloat {
        presentation == .expanded ? Metrics.expandedTopRadius : Metrics.compactTopRadius
    }

    var bottomRadius: CGFloat {
        switch presentation {
        case .idle, .wings: 10
        case .peek(.nowPlaying): 22
        case .peek: 14
        case .expanded: 30
        }
    }

    var islandSize: CGSize {
        let n = notchSize
        let flare = 2 * Metrics.compactTopRadius
        switch presentation {
        case .idle:
            return CGSize(width: n.width + flare, height: n.height)
        case .wings:
            return CGSize(width: n.width + 2 * wingWidth + flare, height: n.height)
        case .peek(.nowPlaying):
            return CGSize(width: max(n.width + 180, 360), height: n.height + 54)
        case .peek:
            return CGSize(width: n.width + 2 * 86 + flare, height: n.height)
        case .expanded:
            return CGSize(width: max(Metrics.expandedWidth, n.width + 400),
                          height: n.height + Metrics.expandedContentHeight)
        }
    }

    func startServices() {
        battery.onEvent = { [weak self] event in
            switch event {
            case .pluggedIn: self?.showPeek(.power(plugged: true))
            case .unplugged: self?.showPeek(.power(plugged: false))
            case .low: self?.showPeek(.lowBattery, seconds: 4)
            }
        }
        timer.onFinish = { [weak self] in self?.showPeek(.timerFinished, seconds: 4) }
        media.onTrackChange = { [weak self] in
            guard let self, Date().timeIntervalSince(self.launchDate) > 3 else { return }
            self.showPeek(.nowPlaying, seconds: 3)
        }
        battery.start()
        media.start()
        calendar.start()
    }

    func showPeek(_ kind: PeekKind, seconds: Double = 2.6) {
        guard !isExpanded else { return }
        peekTask?.cancel()
        peek = kind
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.peek = nil
        }
    }

    func clearPeek() {
        peekTask?.cancel()
        peek = nil
    }
}
