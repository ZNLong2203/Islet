import AppKit
import SwiftUI

/// Now Playing info for any app (Music, Spotify, browsers…).
///
/// Since macOS 15.4 only `com.apple.*` processes may read MediaRemote, so we go through
/// ungive/mediaremote-adapter: `/usr/bin/perl` (an Apple platform binary) loads the adapter
/// framework and streams JSON lines to our stdout pipe.
@Observable @MainActor
final class NowPlayingService {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var artwork: NSImage?
    private(set) var accent: Color = .white
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var bundleID: String? {
        didSet { if bundleID != oldValue { playerIcon = Self.icon(forBundleID: bundleID) } }
    }
    /// Icon of the app that is playing, looked up once per app rather than on every render.
    private(set) var playerIcon: NSImage?
    private(set) var isAvailable = true
    /// Stays true for a few seconds after pausing so the live activity does not flicker away.
    private(set) var showsActivity = false

    private var elapsedAnchor: TimeInterval = 0
    private var anchorDate = Date()
    private var rate: Double = 1

    @ObservationIgnored var onTrackChange: (() -> Void)?

    @ObservationIgnored private var state: [String: Any] = [:]
    @ObservationIgnored private var artworkGeneration = 0
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var lineBuffer = Data()
    @ObservationIgnored private var restarts = 0
    @ObservationIgnored private var hideActivityTask: Task<Void, Never>?
    @ObservationIgnored private let adapter = AdapterPaths.locate()

    var hasMedia: Bool { !title.isEmpty }

    func elapsed(at date: Date) -> TimeInterval {
        var t = elapsedAnchor
        if isPlaying { t += date.timeIntervalSince(anchorDate) * rate }
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }

    // MARK: - Lifecycle

    func start() {
        guard let adapter else {
            isAvailable = false
            NSLog("[NowPlaying] mediaremote-adapter not found; Now Playing disabled")
            return
        }
        killOrphanedAdapters(script: adapter.script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [adapter.script.path, adapter.framework.path, "stream", "--micros", "--debounce=50"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.adapterExited(status: proc.terminationStatus, reason: proc.terminationReason) }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            isAvailable = false
            NSLog("[NowPlaying] failed to launch adapter: \(error)")
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    /// If a previous run crashed, its adapter was re-parented to launchd and keeps running.
    private func killOrphanedAdapters(script: String) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-P", "1", "-f", NSRegularExpression.escapedPattern(for: script)]
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func adapterExited(status: Int32, reason: Process.TerminationReason) {
        process = nil
        // A non-zero exit means the adapter is broken on this macOS; don't hammer it.
        if reason == .exit && status != 0 {
            isAvailable = false
            return
        }
        guard restarts < 5 else { isAvailable = false; return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    // MARK: - Commands

    func togglePlayPause() {
        send(2)
        // Optimistic update so the button reacts instantly.
        elapsedAnchor = elapsed(at: Date())
        anchorDate = Date()
        isPlaying.toggle()
        updateActivity()
    }

    func next() { send(4) }
    func previous() { send(5) }

    func seek(to seconds: TimeInterval) {
        runAdapter(["seek", String(Int(seconds * 1_000_000))])
        elapsedAnchor = seconds
        anchorDate = Date()
    }

    func openPlayerApp() {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func send(_ command: Int) { runAdapter(["send", String(command)]) }

    private func runAdapter(_ args: [String]) {
        guard let adapter else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [adapter.script.path, adapter.framework.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    #if DEBUG
    /// Feed adapter-format JSON lines as if they came from the stream.
    func debugConsume(_ data: Data) { consume(data) }
    #endif

    // MARK: - Stream parsing

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            guard !line.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  var payload = json["payload"] as? [String: Any] else { continue }
            // Artwork is a few hundred KB of base64: decode it once, never keep it in `state`.
            let artwork = payload.removeValue(forKey: "artworkData")
            payload.removeValue(forKey: "artworkMimeType")
            let isDiff = json["diff"] as? Bool == true
            if isDiff {
                for (key, value) in payload {
                    if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
                }
            } else {
                state = payload
            }
            // A full payload without artwork means there is none; a diff without it means unchanged.
            if !isDiff || artwork != nil { applyArtwork(artwork) }
            apply()
        }
    }

    private func apply() {
        let newTitle = state["title"] as? String ?? ""
        let newArtist = state["artist"] as? String ?? ""
        let trackChanged = newTitle != title || newArtist != artist

        title = newTitle
        artist = newArtist
        album = state["album"] as? String ?? ""
        bundleID = state["parentApplicationBundleIdentifier"] as? String ?? state["bundleIdentifier"] as? String
        isPlaying = state["playing"] as? Bool ?? false
        duration = (state["durationMicros"] as? Double ?? 0) / 1_000_000
        elapsedAnchor = (state["elapsedTimeMicros"] as? Double ?? 0) / 1_000_000
        if let ts = state["timestampEpochMicros"] as? Double {
            anchorDate = Date(timeIntervalSince1970: ts / 1_000_000)
        } else {
            anchorDate = Date()
        }
        let reportedRate = state["playbackRate"] as? Double ?? 1
        rate = reportedRate > 0 ? reportedRate : 1

        updateActivity()
        if trackChanged && hasMedia && isPlaying { onTrackChange?() }
    }

    /// Decodes off the main thread and downsamples to the largest size we draw (96pt @2x),
    /// so a track change never stutters the peek animation.
    private func applyArtwork(_ value: Any?) {
        artworkGeneration += 1
        let generation = artworkGeneration
        guard let base64 = value as? String else {
            artwork = nil
            accent = .white
            return
        }
        Task.detached(priority: .userInitiated) {
            let image = Data(base64Encoded: base64).flatMap { Self.thumbnail(from: $0, maxPixelSize: 256) }
            let tint = image?.vibrantAverageColor
            await MainActor.run {
                guard generation == self.artworkGeneration else { return }
                self.artwork = image
                self.accent = Color(nsColor: tint ?? .white)
            }
        }
    }

    private nonisolated static func thumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func updateActivity() {
        hideActivityTask?.cancel()
        if isPlaying && hasMedia {
            showsActivity = true
        } else if showsActivity {
            hideActivityTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.showsActivity = false
            }
        }
    }
}

/// Where the perl script and adapter framework live: inside the .app bundle, or in vendor/ during development.
struct AdapterPaths {
    let script: URL
    let framework: URL

    static func locate() -> AdapterPaths? {
        let fm = FileManager.default
        var candidates: [AdapterPaths] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(AdapterPaths(
                script: resources.appendingPathComponent("mediaremote-adapter.pl"),
                framework: Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework")))
        }
        // `swift run`: walk up from the executable looking for vendor/mediaremote-adapter.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let vendor = dir.appendingPathComponent("vendor/mediaremote-adapter")
            candidates.append(AdapterPaths(
                script: vendor.appendingPathComponent("bin/mediaremote-adapter.pl"),
                framework: vendor.appendingPathComponent("build/MediaRemoteAdapter.framework")))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { fm.fileExists(atPath: $0.script.path) && fm.fileExists(atPath: $0.framework.path) }
    }
}

extension NSImage {
    /// Average colour of the image, pushed toward something bright enough to read on black.
    var vibrantAverageColor: NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s < 0.15 ? s : max(s, 0.55), brightness: max(b, 0.85), alpha: 1)
    }
}
