import AppKit
import SwiftUI

/// What the drop zone is showing: waiting, a drag hovering over it, or the files just added.
@Observable @MainActor
final class DropZoneState {
    var isTargeted = false
    var added = 0
}

/// A small floating target that appears next to the cursor when a dragged file is shaken, so files
/// can be parked on the shelf without carrying them up to the notch.
@MainActor
final class DropZoneController {
    private static let size = CGSize(width: 280, height: 124)

    private let shelf: ShelfStore
    private let state = DropZoneState()
    private let panel: NSPanel
    private var watchTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(shelf: ShelfStore) {
        self.shelf = shelf
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let hosting = DropHostingView(rootView: DropZoneView(state: state))
        hosting.onTargetChange = { [weak state] targeted in state?.isTargeted = targeted }
        hosting.onDrop = { [weak self] pasteboard in self?.accept(pasteboard) ?? false }
        panel.contentView = hosting
    }

    var isVisible: Bool { panel.isVisible }

    func show(near point: NSPoint) {
        hideTask?.cancel()
        state.added = 0
        state.isTargeted = false
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.size.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        watchForRelease()
    }

    func hide() {
        watchTask?.cancel()
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    private func accept(_ pasteboard: NSPasteboard) -> Bool {
        let added = shelf.addFromPasteboard(pasteboard)
        state.added = added
        // A drop that added nothing (already on the shelf) closes quietly.
        scheduleHide(after: added > 0 ? 1.0 : 0.2)
        return added > 0
    }

    /// Closes once the mouse button is up, unless a drop is on its way in.
    private func watchForRelease() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    // The drop callback arrives a moment after the release.
                    self.scheduleHide(after: self.state.isTargeted ? 2.0 : 0.4)
                    return
                }
            }
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }
}

private struct DropZoneView: View {
    let state: DropZoneState

    var body: some View {
        let targeted = state.isTargeted
        let done = state.added > 0
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.92))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(done ? Color.green : (targeted ? Color.accentColor : .white.opacity(0.28)))
                .padding(8)
            VStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(done ? Color.green : (targeted ? Color.accentColor : .white.opacity(0.85)))
                    .symbolEffect(.bounce, value: targeted)
                Text(done ? String(localized: "Added to Shelf") : String(localized: "Drop here to add to Islet"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(targeted || done ? 1 : 0.75))
            }
        }
        .padding(10)
        .frame(width: 280, height: 124)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: targeted)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: done)
    }
}
