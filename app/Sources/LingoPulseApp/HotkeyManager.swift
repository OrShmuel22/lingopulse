import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private let coordinator: AppCoordinator
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var instance: HotkeyManager?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        HotkeyManager.instance = self
        register()
    }

    deinit {
        if let h = handlerRef { RemoveEventHandler(h) }
        if let k = hotKeyRef { UnregisterEventHotKey(k) }
    }

    private func register() {
        // ⌘⌥E (cmd+option+e)
        let modifiers: UInt32 = UInt32(cmdKey | optionKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_E)
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
            DispatchQueue.main.async { HotkeyManager.instance?.coordinator.refineFocusedSelection() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), cb, 1, &spec, nil, &handlerRef)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
