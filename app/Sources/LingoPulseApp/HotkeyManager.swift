import AppKit
import Carbon.HIToolbox

private final class HotkeyContext {
    var onPressed: (() -> Void)?
}

final class HotkeyManager {
    private let context = HotkeyContext()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var keyCode: UInt32
    private var modifiers: UInt32

    init(coordinator: AppCoordinator, keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.context.onPressed = { [weak coordinator] in
            Task { @MainActor in coordinator?.refineFocusedSelection() }
        }
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
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C50_5246), id: 1)
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let cb: EventHandlerProcPtr = { _, _, userData in
            guard let ud = userData else { return noErr }
            let context = Unmanaged<HotkeyContext>.fromOpaque(ud).takeUnretainedValue()
            context.onPressed?()
            return noErr
        }
        let userData = Unmanaged.passUnretained(context).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), cb, 1, &spec, userData, &handlerRef)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
