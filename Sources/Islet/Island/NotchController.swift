import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// Owns the panel and decides when the island expands, collapses and accepts clicks.
@MainActor
final class NotchController {
    let model = IslandModel()

    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var notesHotKey: HotKey?
    private var shelfHotKey: HotKey?
    private var pasteHotKey: HotKey?
    private var isMenuOpen = false
    /// Opened with a shortcut: stays open until the pointer visits the island, or a few seconds pass.
    private var openedByKeyboard = false
    private var keyboardOpenTask: Task<Void, Never>?
    private lazy var dropZone = DropZoneController(shelf: model.shelf)
    private var shake = ShakeDetector()
    private var shakeCooldownUntil: TimeInterval = 0
    /// Change count of the drag pasteboard when the button went down: a shake only counts if a new drag started since.
    private var pressDragChangeCount = 0

    private var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "haptics") }
    }

    /// Shaking a dragged file opens a drop zone beside the cursor.
    private var shakeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "shakeToShelf") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "shakeToShelf") }
    }

    func start() {
        let hosting = DropHostingView(rootView: IslandRootView(model: model))
        hosting.sizingOptions = []
        hosting.targetSize = { [weak self] in self?.model.islandSize ?? .zero }
        hosting.onTargetChange = { [weak self] targeted in
            guard let model = self?.model else { return }
            model.isDropTargeted = targeted
            if targeted { model.tab = .shelf }
        }
        hosting.onDrop = { [weak self] pasteboard in
            (self?.model.shelf.addFromPasteboard(pasteboard) ?? 0) > 0
        }
        panel.contentView = hosting
        panel.keyPolicy = { [weak self] in
            guard let self else { return false }
            return self.model.isExpanded && self.model.tab == .notes
        }
        panel.onEscape = { [weak self] in self?.collapse() }
        model.onOpenSettings = { [weak self] in self?.showSettingsMenu() }

        layout()
        panel.orderFrontRegardless()

        installMouseMonitors()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.media.stop() }
        }

        // ⌃⌥N: drop the island down straight into Notes, from anywhere.
        notesHotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey, id: 1) { [weak self] in
            MainActor.assumeIsolated { self?.toggleNotes() }
        }

        // ⌃⌥D opens or closes the shelf, ⌃⌥V puts the clipboard on it.
        shelfHotKey = HotKey(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey, id: 2) { [weak self] in
            MainActor.assumeIsolated { self?.toggleShelf() }
        }
        pasteHotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey, id: 3) { [weak self] in
            MainActor.assumeIsolated { _ = self?.model.shelf.addFromPasteboard() }
        }

        // Menus and drags out of the shelf must not be interrupted by the island collapsing.
        for (name, open) in [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.isMenuOpen = open
                    if !open { self?.handleMouse() }
                }
            }
        }

        model.startServices()
        enableLaunchAtLoginOnce()
        #if DEBUG
        installDebugHook()
        #endif
    }

    #if DEBUG
    private var debugPinned = false

    /// Drive the island from a shell for screenshots:
    /// `notifyutil`-style via DistributedNotificationCenter, name `io.github.znlong2203.islet.debug`,
    /// object `expand:<tab>` | `collapse` | `peek:<power|unplugged|low|timer|track>` | `media:<json file>` |
    /// `timer:<minutes>` | `lang:<system|en|vi>` | `shelf-add:<path>` | `shelf-paste` | `shelf-select[:<name part>]` |
    /// `shelf-clear` | `shelf-zip` | `shelf-dump:<file>` | `state:<file>` | `dropzone`.
    private func installDebugHook() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("io.github.znlong2203.islet.debug"), object: nil, queue: .main
        ) { [weak self] note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { self?.runDebug(command) }
        }
    }

    private func runDebug(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "expand":
            debugPinned = true
            expand(tab: ExpandedTab(rawValue: arg) ?? .home)
        case "collapse":
            debugPinned = false
            collapse()
        case "peek":
            let kinds: [String: PeekKind] = ["power": .power(plugged: true), "unplugged": .power(plugged: false), "low": .lowBattery,
                                             "timer": .timerFinished, "track": .nowPlaying]
            if let kind = kinds[arg] { model.showPeek(kind, seconds: 6) }
        case "media":
            if let data = FileManager.default.contents(atPath: arg) { model.media.debugConsume(data) }
        case "timer":
            model.timer.set(minutes: Int(arg) ?? 25)
            model.timer.start()
        case "lang":
            if let language = AppLanguage(rawValue: arg) { setLanguage(language) }
        case "shelf-add":
            model.shelf.add([.file(URL(fileURLWithPath: arg))])
        case "shelf-paste":
            _ = model.shelf.addFromPasteboard()
        case "shelf-select":
            let names = arg.split(separator: ",").map(String.init)
            model.shelf.selection = Set(model.shelf.items.filter { item in
                names.isEmpty || names.contains { item.url.lastPathComponent.contains($0) }
            }.map(\.id))
        case "shelf-clear":
            model.shelf.remove(Set(model.shelf.items.map(\.id)))
        case "shelf-zip":
            model.shelf.zip(model.shelf.targets)
        case "shelf-dump":
            let lines = model.shelf.items.map { "\($0.url.path)\t\($0.isOwned ? "owned" : "ref")\t\(model.shelf.selection.contains($0.id) ? "sel" : "-")" }
            try? lines.joined(separator: "\n").write(toFile: arg, atomically: true, encoding: .utf8)
        case "state":
            let text = "expanded=\(model.isExpanded) menuOpen=\(model.isMenuOpen) draggingOut=\(model.isDraggingOut) targeted=\(model.isDropTargeted)"
            try? text.write(toFile: arg, atomically: true, encoding: .utf8)
        case "dropzone":
            dropZone.show(near: NSEvent.mouseLocation)
        default:
            break
        }
    }
    #endif

    private func layout() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        self.screen = screen
        model.notchSize = NotchGeometry.notchSize(for: screen)
        let size = Metrics.windowSize(notch: model.notchSize)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height),
                       display: true)
    }

    // MARK: - Mouse

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask.union(.leftMouseDown), handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.trackShake(event)
                if event.type != .leftMouseDown { self?.handleMouse() }
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) { monitors.append(local) }
    }

    /// Watches other apps' drags for a shake. The drag pasteboard is only read once a shake is seen.
    private func trackShake(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressDragChangeCount = NSPasteboard(name: .drag).changeCount
            shake.reset()
        case .leftMouseDragged:
            guard shakeEnabled, event.timestamp > shakeCooldownUntil, !dropZone.isVisible,
                  shake.feed(x: NSEvent.mouseLocation.x, at: event.timestamp) else { return }
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != pressDragChangeCount,
                  pasteboard.canReadObject(forClasses: [NSURL.self, NSImage.self], options: nil) else { return }
            shakeCooldownUntil = event.timestamp + 1.5
            dropZone.show(near: NSEvent.mouseLocation)
        default:
            break
        }
    }

    /// Island frame in screen coordinates for the current presentation.
    private func islandRect() -> NSRect {
        guard let screen else { return .zero }
        let size = model.islandSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height + 2)
    }

    private func handleMouse() {
        guard let screen else { return }
        let mouse = NSEvent.mouseLocation
        let expanded = model.isExpanded
        // This runs on every mouse move system-wide: bail out early unless the cursor is near the notch.
        if !expanded && hoverTask == nil && mouse.y < screen.frame.maxY - 120 { return }

        let island = islandRect()
        let hotZone = expanded ? island.insetBy(dx: -14, dy: -14) : island.insetBy(dx: -6, dy: -4)
        let inside = hotZone.contains(mouse)

        // Clicks outside the island fall through to whatever is underneath.
        let ignoresMouse = !(expanded && island.contains(mouse))
        if panel.ignoresMouseEvents != ignoresMouse { panel.ignoresMouseEvents = ignoresMouse }

        if inside {
            // Once the pointer arrives, hovering takes over from the shortcut.
            if openedByKeyboard { releaseKeyboardOpen() }
            guard !expanded else { hoverTask?.cancel(); hoverTask = nil; return }
            guard hoverTask == nil else { return }
            let dragging = NSEvent.pressedMouseButtons & 1 != 0
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(dragging ? 40 : 110))
                guard !Task.isCancelled, let self else { return }
                self.hoverTask = nil
                self.expand(tab: dragging ? .shelf : nil)
            }
        } else {
            guard expanded else { hoverTask?.cancel(); hoverTask = nil; return }
            guard hoverTask == nil, !keepsOpen else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled, let self else { return }
                self.hoverTask = nil
                if !self.keepsOpen { self.collapse() }
            }
        }
    }

    /// Typing a note or using the settings menu should not be interrupted by the mouse drifting away.
    private var keepsOpen: Bool {
        #if DEBUG
        if debugPinned { return true }
        #endif
        return openedByKeyboard || isMenuOpen || model.isMenuOpen || model.isDraggingOut || model.isDropTargeted || (panel.isKeyWindow && model.tab == .notes)
    }

    func expand(tab: ExpandedTab? = nil) {
        if let tab { model.tab = tab }
        model.clearPeek()
        model.isExpanded = true
        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        handleMouse()
    }

    func collapse() {
        releaseKeyboardOpen()
        hoverTask?.cancel()
        hoverTask = nil
        model.isExpanded = false
        if panel.isKeyWindow {
            // Hand keyboard focus back to the app the user was in.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
    }

    private func toggleShelf() {
        if model.isExpanded && model.tab == .shelf {
            collapse()
            return
        }
        // Set before expanding, or the pointer being elsewhere would collapse it straight away.
        openedByKeyboard = true
        keyboardOpenTask?.cancel()
        keyboardOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.releaseKeyboardOpen()
            self?.handleMouse()
        }
        expand(tab: .shelf)
    }

    private func releaseKeyboardOpen() {
        openedByKeyboard = false
        keyboardOpenTask?.cancel()
        keyboardOpenTask = nil
    }

    private func toggleNotes() {
        if model.isExpanded && model.tab == .notes && panel.isKeyWindow {
            collapse()
            return
        }
        expand(tab: .notes)
        panel.makeKeyAndOrderFront(nil)
        model.notesFocusRequest += 1
    }

    // MARK: - Settings

    private func showSettingsMenu() {
        let menu = NSMenu()

        let haptics = NSMenuItem(title: String(localized: "Haptic feedback"), action: #selector(MenuTarget.toggleHaptics), keyEquivalent: "")
        haptics.state = hapticsEnabled ? .on : .off
        menu.addItem(haptics)

        let shake = NSMenuItem(title: String(localized: "Shake a dragged file to open drop zone"), action: #selector(MenuTarget.toggleShake), keyEquivalent: "")
        shake.state = shakeEnabled ? .on : .off
        menu.addItem(shake)

        let removeAfterDrag = NSMenuItem(title: String(localized: "Remove from shelf after dragging out"), action: #selector(MenuTarget.toggleRemoveAfterDrag), keyEquivalent: "")
        removeAfterDrag.state = model.shelf.removesAfterDrag ? .on : .off
        menu.addItem(removeAfterDrag)

        let login = NSMenuItem(title: String(localized: "Launch at login"), action: #selector(MenuTarget.toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !model.calendar.isAuthorized {
            menu.addItem(NSMenuItem(title: String(localized: "Connect Calendar…"), action: #selector(MenuTarget.connectCalendar), keyEquivalent: ""))
        }

        let languages = NSMenu()
        let current = AppLanguage.current
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(MenuTarget.setLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.rawValue
            item.state = language == current ? .on : .off
            languages.addItem(item)
        }
        let languageItem = NSMenuItem(title: String(localized: "Language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        menu.addItem(languageItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Islet"), action: #selector(MenuTarget.quit), keyEquivalent: "q"))

        let target = MenuTarget(controller: self)
        (menu.items + languages.items).forEach { $0.target = target }

        isMenuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        isMenuOpen = false
        withExtendedLifetime(target) {}
        handleMouse()
    }

    fileprivate func toggleHaptics() { hapticsEnabled.toggle() }
    fileprivate func toggleShake() { shakeEnabled.toggle() }
    fileprivate func toggleRemoveAfterDrag() { model.shelf.removesAfterDrag.toggle() }

    /// The first launch from /Applications turns on start-at-login; the ⚙️ menu can turn it off.
    private func enableLaunchAtLoginOnce() {
        let key = "loginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key), Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("[Settings] launch at login failed: \(error)")
        }
    }

    fileprivate func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[Settings] launch at login failed: \(error)")
        }
    }

    fileprivate func connectCalendar() { model.calendar.requestAccess() }

    /// Bundles pick their localization at launch, so switching language means relaunching.
    fileprivate func setLanguage(_ language: AppLanguage) {
        guard language != AppLanguage.current else { return }
        language.apply()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}

/// UI language override, stored as the app's own `AppleLanguages` default.
enum AppLanguage: String, CaseIterable {
    case system, english = "en", vietnamese = "vi"

    /// Each language is listed under its own name so it can be found whatever the UI is set to.
    var title: String {
        switch self {
        case .system: String(localized: "System default")
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }

    static var current: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        let override = (domain?["AppleLanguages"] as? [String])?.first
        return override.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// NSMenu needs an Objective-C target for its actions.
private final class MenuTarget: NSObject {
    weak var controller: NotchController?

    init(controller: NotchController) { self.controller = controller }

    @objc func toggleHaptics() { MainActor.assumeIsolated { controller?.toggleHaptics() } }
    @objc func toggleShake() { MainActor.assumeIsolated { controller?.toggleShake() } }
    @objc func toggleRemoveAfterDrag() { MainActor.assumeIsolated { controller?.toggleRemoveAfterDrag() } }
    @objc func toggleLogin() { MainActor.assumeIsolated { controller?.toggleLogin() } }
    @objc func connectCalendar() { MainActor.assumeIsolated { controller?.connectCalendar() } }
    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        MainActor.assumeIsolated { controller?.setLanguage(language) }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
