import AppKit
import SwiftUI

/// A transparent AppKit layer over a shelf tile.
///
/// SwiftUI's `onDrag` carries one item and never says whether the drop happened, so the tile hands
/// its mouse events to AppKit: click selects, double-click opens, dragging takes the whole selection
/// along, and a right-click shows the item's menu.
struct ShelfTileSurface: NSViewRepresentable {
    var toolTip: String
    /// Files to drag, resolved when the drag starts so it reflects the current selection.
    var dragURLs: () -> [URL]
    var onClick: () -> Void
    var onOpen: () -> Void
    var onHover: (Bool) -> Void
    var onDragBegan: () -> Void
    var onDragEnded: (_ delivered: Bool, _ urls: [URL]) -> Void
    var menu: () -> NSMenu

    func makeNSView(context: Context) -> TileSurfaceView { TileSurfaceView() }

    func updateNSView(_ view: TileSurfaceView, context: Context) {
        view.toolTip = toolTip
        view.dragURLs = dragURLs
        view.onClick = onClick
        view.onOpen = onOpen
        view.onHover = onHover
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        view.menuProvider = menu
    }
}

final class TileSurfaceView: NSView {
    var dragURLs: () -> [URL] = { [] }
    var onClick: () -> Void = {}
    var onOpen: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onDragBegan: () -> Void = {}
    var onDragEnded: (Bool, [URL]) -> Void = { _, _ in }
    var menuProvider: () -> NSMenu = { NSMenu() }

    private var mouseDownPoint: NSPoint?
    private var dragStarted = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragStarted = false
        if event.clickCount == 2 { onOpen() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        dragStarted = true
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if !dragStarted && event.clickCount == 1 { onClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }

    private func beginDrag(with event: NSEvent) {
        let urls = dragURLs()
        guard !urls.isEmpty else { return }
        let size: CGFloat = 48
        let origin = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            let offset = CGFloat(min(index, 4)) * 5
            item.setDraggingFrame(NSRect(x: origin.x - size / 2 + offset, y: origin.y - size / 2 - offset,
                                         width: size, height: size), contents: icon)
            return item
        }
        let source = ShelfDragSource(urls: urls, onBegan: onDragBegan, onEnded: onDragEnded)
        let session = beginDraggingSession(with: items, event: event, source: source)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

/// Reports where a drag out of the shelf ended up. The session keeps it alive until then, even if
/// the island collapses and the tile that started the drag goes away.
@MainActor
private final class ShelfDragSource: NSObject, NSDraggingSource {
    private static var live: [ObjectIdentifier: ShelfDragSource] = [:]

    private let urls: [URL]
    private let onBegan: () -> Void
    private let onEnded: (Bool, [URL]) -> Void

    init(urls: [URL], onBegan: @escaping () -> Void, onEnded: @escaping (Bool, [URL]) -> Void) {
        self.urls = urls
        self.onBegan = onBegan
        self.onEnded = onEnded
        super.init()
        Self.live[ObjectIdentifier(self)] = self
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onBegan() }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnded(!operation.isEmpty, urls)
        Self.live[ObjectIdentifier(self)] = nil
    }
}

/// An NSMenuItem that runs a closure, so context menus can be built inline.
final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void

    init(_ title: String, symbol: String? = nil, block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { block() }
}
