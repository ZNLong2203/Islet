import Carbon.HIToolbox

/// System-wide shortcut via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        HotKey.actions[id] = action
        let hotKeyID = EventHotKeyID(signature: OSType(0x444E_4953), id: id) // 'DNIS'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
