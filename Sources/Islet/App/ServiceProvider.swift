import AppKit

/// Answers "Add to Islet" from the Services menu: Finder's right-click menu for files and folders,
/// and the Services menu for selected text in any app.
final class ServiceProvider: NSObject {
    private let model: IslandModel

    init(model: IslandModel) { self.model = model }

    @objc(addToShelf:userData:error:)
    func addToShelf(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        MainActor.assumeIsolated { _ = model.shelf.addFromPasteboard(pasteboard) }
    }
}
