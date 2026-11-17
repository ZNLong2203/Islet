import AppKit
import SwiftUI

/// An NSHostingView that takes drops itself and hands over the drag pasteboard.
///
/// SwiftUI's `onDrop(of:)` delivers one representation per item, picked from the types it was
/// given. A dragged .txt file therefore arrives as plain text instead of as the file. Reading
/// the pasteboard directly lets the shelf prefer real files over their contents.
final class DropHostingView<Content: View>: NSHostingView<Content> {
    /// Size of the area that accepts drops, hugging the top centre of the view. Nil means the whole view.
    var targetSize: (() -> CGSize)?
    var onTargetChange: (Bool) -> Void = { _ in }
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

    private var isTargeted = false

    private static var acceptedTypes: [NSPasteboard.PasteboardType] { [.fileURL, .URL, .png, .tiff, .string] }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { setTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setTargeted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setTargeted(false)
        return onDrop(sender.draggingPasteboard)
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let inside = accepts(convert(sender.draggingLocation, from: nil))
        setTargeted(inside)
        return inside ? .copy : []
    }

    private func accepts(_ point: NSPoint) -> Bool {
        guard let size = targetSize?() else { return true }
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        return abs(point.x - bounds.midX) <= size.width / 2 && fromTop >= 0 && fromTop <= size.height
    }

    private func setTargeted(_ targeted: Bool) {
        guard targeted != isTargeted else { return }
        isTargeted = targeted
        onTargetChange(targeted)
    }
}
