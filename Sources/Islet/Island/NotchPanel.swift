import AppKit

/// Borderless, transparent panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    /// The panel only takes keyboard focus when this says so (the Notes tab); otherwise
    /// clicking a button in the island would steal typing from the app underneath.
    var keyPolicy: (() -> Bool)?
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { keyPolicy?() ?? false }
    override var canBecomeMain: Bool { false }

    /// Keep the window where we put it, even though it overlaps the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        // Catch Esc before NSTextView turns it into autocomplete.
        if event.type == .keyDown && event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}
