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
    private var isMenuOpen = false

    private var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "haptics") }
    }

    func start() {
        let hosting = NSHostingView(rootView: IslandRootView(model: model))
        hosting.sizingOptions = []
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
    /// object `expand:<tab>` | `collapse` | `peek:<power|low|timer|track>` | `media:<json file>` |
    /// `timer:<minutes>` | `lang:<system|en|vi>`.
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
            let kinds: [String: PeekKind] = ["power": .power(plugged: true), "low": .lowBattery,
                                             "timer": .timerFinished, "track": .nowPlaying]
            if let kind = kinds[arg] { model.showPeek(kind, seconds: 6) }
        case "media":
            if let data = FileManager.default.contents(atPath: arg) { model.media.debugConsume(data) }
        case "timer":
            model.timer.set(minutes: Int(arg) ?? 25)
            model.timer.start()
        case "lang":
            if let language = AppLanguage(rawValue: arg) { setLanguage(language) }
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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) { monitors.append(local) }
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
        return isMenuOpen || model.isDropTargeted || (panel.isKeyWindow && model.tab == .notes)
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
    @objc func toggleLogin() { MainActor.assumeIsolated { controller?.toggleLogin() } }
    @objc func connectCalendar() { MainActor.assumeIsolated { controller?.connectCalendar() } }
    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        MainActor.assumeIsolated { controller?.setLanguage(language) }
    }
    @objc func quit() { NSApp.terminate(nil) }
}
