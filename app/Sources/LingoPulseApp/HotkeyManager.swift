import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private let coordinator: AppCoordinator
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var instance: HotkeyManager?
    private var keyCode: UInt32
    private var modifiers: UInt32

    init(coordinator: AppCoordinator, keyCode: UInt32, modifiers: UInt32) {
        self.coordinator = coordinator
        self.keyCode = keyCode
        self.modifiers = modifiers
        HotkeyManager.instance = self
        register()
    }

    deinit {
        if let h = handlerRef { RemoveEventHandler(h) }
        if let k = hotKeyRef { UnregisterEventHotKey(k) }
    }

    func rebind(keyCode: UInt32, modifiers: UInt32) {
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        if let k = hotKeyRef { UnregisterEventHotKey(k); hotKeyRef = nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        register()
        Log.info("hotkey rebound to keyCode=\(keyCode) modifiers=\(modifiers)")
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C50_5246), id: 1) // 'LPRF'
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let cb: EventHandlerProcPtr = { _, eventRef, _ in
            guard let event = eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            Task { @MainActor in HotkeyManager.instance?.coordinator.refineFocusedSelection() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), cb, 1, &spec, nil, &handlerRef)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
