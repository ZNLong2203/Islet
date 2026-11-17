import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var serviceProvider: ServiceProvider?
    private var sigterm: DispatchSourceSignal?
    /// Files handed over by `open -a Islet file` can arrive before the island exists.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Route `kill`/logout through the normal quit path so the media adapter child gets stopped.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
        self.sigterm = sigterm

        let controller = NotchController()
        controller.start()
        self.controller = controller

        let provider = ServiceProvider(model: controller.model)
        NSApp.servicesProvider = provider
        serviceProvider = provider
        NSUpdateDynamicServices()

        addToShelf(pendingURLs)
        pendingURLs = []
    }

    /// `open -a Islet file`, or a file dropped on the app's icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if controller == nil { pendingURLs += urls } else { addToShelf(urls) }
    }

    private func addToShelf(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        controller?.model.shelf.add(files.map(ShelfStore.Payload.file))
    }
}
