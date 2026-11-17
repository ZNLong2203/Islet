import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Temporary shelf: park files, images, links and text, then drag them out, share or zip them.
///
/// Files stay where they are and the shelf only remembers the path. Anything Islet makes itself
/// (a text snippet, a pasted image, a link, a zip) lives in `storageURL` and goes away with its item.
@Observable @MainActor
final class ShelfStore {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL

        /// Created by Islet, so it is deleted from disk when the item is removed.
        var isOwned: Bool { url.path.hasPrefix(ShelfStore.storageURL.path + "/") }
    }

    /// What a drop or the clipboard can hand over, in the order Islet prefers it.
    enum Payload: Sendable {
        case file(URL)
        case image(Data, UTType)
        case link(URL)
        case text(String)
    }

    nonisolated static let storageURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Islet/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private(set) var items: [Item] = []
    private(set) var thumbnails: [URL: NSImage] = [:]
    var selection: Set<Item.ID> = []
    private(set) var isBusy = false
    /// Called with how many items one drop, paste or service call added.
    @ObservationIgnored var onAdded: ((Int) -> Void)?

    private let defaultsKey = "shelf.paths"

    /// Dragging items out of the shelf also takes them off it (like moving), when switched on.
    var removesAfterDrag: Bool {
        get { UserDefaults.standard.bool(forKey: "shelf.removeAfterDrag") }
        set { UserDefaults.standard.set(newValue, forKey: "shelf.removeAfterDrag") }
    }

    /// What an action applies to: the selection, or everything when nothing is selected.
    var targets: [Item] { selection.isEmpty ? items : items.filter { selection.contains($0.id) } }

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { Item(url: $0) }
        items.forEach { loadThumbnail(for: $0.url) }
        persist()
        removeStrayOwnedFiles()
    }

    // MARK: - Adding

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            let url = url.standardizedFileURL
            guard !items.contains(where: { $0.url == url }) else { continue }
            items.append(Item(url: url))
            loadThumbnail(for: url)
            added += 1
        }
        if added > 0 { persist() }
        return added
    }

    /// Stores payloads (writing files for text, images and links) and reports once.
    @discardableResult
    func add(_ payloads: [Payload]) -> Int {
        let urls = payloads.compactMap { payload -> URL? in
            switch payload {
            case .file(let url): url
            case .image(let data, let type): writeImage(data, type: type)
            case .link(let url): writeLink(url)
            case .text(let text): writeText(text)
            }
        }
        let added = add(urls)
        if added > 0 { onAdded?(added) }
        return added
    }

    /// What the clipboard, a drop or a service call carries, most specific first: real files, then an
    /// image, then a web link, then plain text. A file always wins, so dragging a .txt file adds the
    /// file itself rather than a copy of its text.
    @discardableResult
    func addFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Int {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return add(files.map(Payload.file)) }
        if let data = pasteboard.data(forType: .png) { return add([.image(data, .png)]) }
        if let data = pasteboard.data(forType: .tiff) { return add([.image(data, .tiff)]) }
        if let link = pasteboard.string(forType: .URL).flatMap(URL.init(string:)), Self.isWebLink(link) {
            return add([.link(link)])
        }
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if let link = URL(string: text), Self.isWebLink(link), !text.contains(where: \.isWhitespace) {
                return add([.link(link)])
            }
            return add([.text(text)])
        }
        return 0
    }

    private static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && url.host != nil
    }

    // MARK: - Removing

    /// `keepFilesFor` delays deleting Islet's own files, for items just dragged out: the receiving app
    /// may still be copying them after the drop.
    func remove(_ ids: Set<Item.ID>, keepFilesFor delay: Duration = .zero) {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        let owned = removed.filter(\.isOwned).map(\.url)
        if delay == .zero {
            owned.forEach { try? FileManager.default.removeItem(at: $0) }
        } else if !owned.isEmpty {
            Task.detached {
                try? await Task.sleep(for: delay)
                owned.forEach { try? FileManager.default.removeItem(at: $0) }
            }
        }
        persist()
    }

    func remove(_ item: Item) { remove([item.id]) }

    /// Removes the selection, or everything when nothing is selected.
    func removeTargets() { remove(Set(targets.map(\.id))) }

    /// Forget items whose file was moved or deleted behind the shelf's back.
    func prune() {
        let missing = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !missing.isEmpty { remove(Set(missing.map(\.id))) }
    }

    func toggleSelection(_ item: Item) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    /// Items dragged out of the shelf: gone from it when "remove after dragging" is on.
    func finishedDragOut(_ urls: [URL]) {
        guard removesAfterDrag else { return }
        let ids = Set(items.filter { urls.contains($0.url) }.map(\.id))
        remove(ids, keepFilesFor: .seconds(180))
    }

    // MARK: - Actions

    func airDrop(_ items: [Item]) {
        guard !items.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: items.map(\.url))
    }

    func copyToClipboard(_ items: [Item]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
    }

    func open(_ item: Item) { NSWorkspace.shared.open(item.url) }

    func reveal(_ items: [Item]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    /// Compresses the items into one zip, which joins the shelf.
    func zip(_ items: [Item]) {
        guard !items.isEmpty, !isBusy else { return }
        isBusy = true
        let sources = items.map(\.url)
        let name = sources.count == 1 ? sources[0].deletingPathExtension().lastPathComponent : String(localized: "Archive")
        let output = uniqueURL(name: name, ext: "zip")
        Task {
            let made = await Task.detached(priority: .userInitiated) { Self.makeArchive(of: sources, at: output) }.value
            isBusy = false
            if made, add([output]) > 0 {
                selection = Set(self.items.filter { $0.url == output }.map(\.id))
            }
        }
    }

    /// Zips through a folder of links, so files from different places end up side by side without copying them first.
    nonisolated private static func makeArchive(of sources: [URL], at output: URL) -> Bool {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("islet-zip-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            var used = Set<String>()
            for source in sources {
                var name = source.lastPathComponent
                var counter = 2
                while !used.insert(name).inserted {
                    name = "\(source.deletingPathExtension().lastPathComponent) \(counter)"
                        + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
                    counter += 1
                }
                try manager.createSymbolicLink(at: staging.appendingPathComponent(name), withDestinationURL: source)
            }
        } catch {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-qr", output.path, "."]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 && manager.fileExists(atPath: output.path)
    }

    // MARK: - Files Islet creates

    private func writeText(_ text: String) -> URL? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let url = uniqueURL(name: Self.fileName(from: firstLine, fallback: String(localized: "Text snippet")), ext: "txt")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }

    private func writeImage(_ data: Data, type: UTType) -> URL? {
        let stamp = Self.stamp.string(from: Date())
        let keeps: [UTType] = [.png, .jpeg, .gif, .heic, .webP]
        if keeps.contains(type), let ext = type.preferredFilenameExtension {
            let url = uniqueURL(name: "\(String(localized: "Image")) \(stamp)", ext: ext)
            do { try data.write(to: url) } catch { return nil }
            return url
        }
        // TIFF and other formats become PNG so every app can read them.
        guard let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) else { return nil }
        let url = uniqueURL(name: "\(String(localized: "Image")) \(stamp)", ext: "png")
        do { try png.write(to: url) } catch { return nil }
        return url
    }

    /// A .webloc, which Finder and browsers open like any bookmark.
    private func writeLink(_ link: URL) -> URL? {
        let name = Self.fileName(from: link.host ?? link.absoluteString, fallback: String(localized: "Link"))
        let url = uniqueURL(name: name, ext: "webloc")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static func fileName(from text: String, fallback: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let name = String(cleaned.prefix(36)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name.hasPrefix(".") ? fallback : name
    }

    nonisolated private func uniqueURL(name: String, ext: String) -> URL {
        let manager = FileManager.default
        var url = Self.storageURL.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while manager.fileExists(atPath: url.path) {
            url = Self.storageURL.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return url
    }

    /// Files left in the storage folder by an earlier run (a crash, or items cleared elsewhere).
    private func removeStrayOwnedFiles() {
        let kept = Set(items.map(\.url.path))
        let contents = (try? FileManager.default.contentsOfDirectory(at: Self.storageURL, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !kept.contains(url.standardizedFileURL.path) && !kept.contains(url.path) {
            try? FileManager.default.removeItem(at: url)
        }
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
