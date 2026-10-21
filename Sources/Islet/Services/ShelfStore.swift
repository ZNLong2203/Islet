import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Temporary file shelf: drop files on the notch, drag them out later or AirDrop them.
@Observable @MainActor
final class ShelfStore {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL
    }

    private(set) var items: [Item] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    private let defaultsKey = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { Item(url: $0) }
        items.forEach { loadThumbnail(for: $0.url) }
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(Item(url: url))
        loadThumbnail(for: url)
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func airDropAll() {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items.map(\.url))
    }

    /// Accepts file URLs from a SwiftUI drop.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let nsurl = object as? NSURL else { return }
                let url = nsurl.filePathURL ?? (nsurl as URL)
                DispatchQueue.main.async { self.add(url) }
            }
        }
        return accepted
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }

    private func loadThumbnail(for url: URL) {
        thumbnails[url] = NSWorkspace.shared.icon(forFile: url.path)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.thumbnails[url] = image }
        }
    }
}
