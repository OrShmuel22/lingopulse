import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let refine       = Self("refine",       default: .init(.e, modifiers: [.command, .option]))
    static let preview      = Self("preview",      default: .init(.e, modifiers: [.command, .option, .shift]))
    static let undo         = Self("undo",         default: .init(.z, modifiers: [.command, .option]))
    static let tone         = Self("tone",         default: .init(.t, modifiers: [.command, .option]))
    static let dictionary   = Self("dictionary",   default: .init(.s, modifiers: [.command, .option]))
    static let captureStyle = Self("captureStyle", default: .init(.m, modifiers: [.command, .option]))
}

@MainActor
final class HotkeyManager {
    init(coordinator: AppCoordinator) {
        KeyboardShortcuts.onKeyDown(for: .refine)       { [weak coordinator] in coordinator?.refineFocusedSelection() }
        KeyboardShortcuts.onKeyDown(for: .preview)      { [weak coordinator] in coordinator?.previewSelection() }
        KeyboardShortcuts.onKeyDown(for: .undo)         { [weak coordinator] in coordinator?.undoLast() }
        KeyboardShortcuts.onKeyDown(for: .tone)         { [weak coordinator] in coordinator?.refineWithTone() }
        KeyboardShortcuts.onKeyDown(for: .dictionary)   { [weak coordinator] in coordinator?.lookupWord() }
        KeyboardShortcuts.onKeyDown(for: .captureStyle) { [weak coordinator] in coordinator?.captureStyleExample() }
    }
}
