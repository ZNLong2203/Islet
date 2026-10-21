import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var sigterm: DispatchSourceSignal?

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
    }
}
