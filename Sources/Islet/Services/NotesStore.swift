import AppKit

/// A scratchpad that lives in the notch and survives restarts.
@Observable @MainActor
final class NotesStore {
    private static let defaultsKey = "notes.text"

    var text: String = UserDefaults.standard.string(forKey: NotesStore.defaultsKey) ?? "" {
        didSet { UserDefaults.standard.set(text, forKey: Self.defaultsKey) }
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() { text = "" }
}
