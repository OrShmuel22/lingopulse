# Quick Refine & Copy — Design

**Date:** 2026-05-03
**Status:** Approved, ready for implementation plan

## Problem

Apps like Claude Code's terminal, iTerm, and Cursor's terminal pane don't expose AX text, so Right-⌘ refine and Live Mode don't work there. The current workaround is to type the prompt in Notes, refine it, copy, switch back, and paste. Quick Refine collapses that into a keyboard-driven scratchpad that lives next to the existing Quick Action menu, with the refined result shown for review before it lands on the clipboard.

## User-facing flow

1. Double-tap ⇧ → Quick Action menu now lists: Preview · Refine · Tone · **Quick Refine** · Undo.
2. Pick Quick Refine (key `4`) → `QuickRefineCapturePanel` opens centered, textarea focused.
3. Type or paste. Enter submits; Shift+Enter inserts a newline; Esc cancels.
4. On submit → existing `TonePickerPanel` opens.
5. On tone pick → `Fixer.refine(selection:, app:, toneOverride:)` runs.
6. On result → existing `PreviewPanel.show(..., axWriteAvailable: false, ...)` opens. The `false` flag triggers the existing auto-copy on open and the "Refined copied — press Esc to dismiss, then ⌘V" banner.
7. Enter accepts (no-op for AX write — text is already on clipboard). Esc rejects (rolls back ring entry, same as today).

## Architecture

Pure composition over existing components. No new business logic, no changes to `Fixer`, `Prompts`, `OllamaService`, `RingBuffer`, or `HistoryStore`.

```
QuickAction (.quickRefine)
        │
        ▼
AppCoordinator.runQuickRefine()
        │
        ▼
QuickRefineCommand.execute()
        │
        ▼
┌─────────────────────────────┐
│ QuickRefineCapturePanel     │  new
│   - textarea (Enter submit) │
│   - returns String?         │
└──────────────┬──────────────┘
               │ trimmed text
               ▼
┌─────────────────────────────┐
│ TonePickerPanel             │  existing
│   - returns Tone?           │
└──────────────┬──────────────┘
               │
               ▼
        Fixer.refine(
          selection: text,
          app: "QuickRefine",
          toneOverride: tone)
               │
               ▼
┌─────────────────────────────┐
│ PreviewPanel                │  existing
│   axWriteAvailable: false   │
│   onAccept: no-op           │
│   onReject: ring rollback   │
└─────────────────────────────┘
```

## New components

### `Views/QuickRefineCapturePanel.swift`

Borderless `KeyablePanel` with an `NSTextView` (multi-line) and a footer with shortcut hints. Mirrors `PreviewPanel`'s window/monitor lifecycle:

- self-retain via `selfReference` for the panel's visible lifetime;
- local `NSEvent` monitor for Enter / Shift+Enter / Esc;
- global key monitor for Esc dismissal when source app keeps focus;
- global mouse monitor for outside-click dismissal;
- saves and restores `previousApp` on close.

Public surface:

```swift
@MainActor
final class QuickRefineCapturePanel {
    func show(onPick: @escaping (String?) -> Void)
    func close()
}
```

`onPick` fires once with the trimmed input on Enter, or `nil` on cancel.

Footer hints: `↩ Refine` · `⇧↩ Newline` · `Esc Cancel`.

Panel size ~520×220, centered on the main screen (no anchor — there is no source field).

### `Commands/QuickRefineCommand.swift`

Thin orchestrator. No accessibility or refine-state coupling; it does not write to the source field.

```swift
@MainActor
final class QuickRefineCommand {
    private let fixer: Fixer
    private let notify: (String, String) -> Void

    init(fixer: Fixer, notify: @escaping (String, String) -> Void = …)

    func execute() async
}
```

Steps:

1. `await capture()` → `String?`. Empty/whitespace-only → return silently.
2. `await pickTone()` → `Tone?`. Nil → return silently.
3. `try await fixer.refine(selection:, app: "QuickRefine", toneOverride: tone.description)`.
4. `await PreviewPanel().show(..., axWriteAvailable: false, onAccept: {}, onReject: { rollback })`.

### `QuickAction.quickRefine`

New enum case in `Views/QuickActionPanel.swift`:

```swift
enum QuickAction: Int, CaseIterable, Identifiable {
    case preview = 1, refine, tone, quickRefine, undo
    …
}
```

- `label`: `"Quick Refine"`.
- `systemImage`: `square.and.pencil`.
- `shortcutHint`: `"4"`. Undo becomes `"5"`.

`QuickActionPanel.handleKey` digit guard widens from `1...4` to `1...5`.

## Touched files

| File | Change |
|------|--------|
| `app/Sources/LingoPulseApp/Views/QuickActionPanel.swift` | Add `.quickRefine` case; widen digit guard. |
| `app/Sources/LingoPulseApp/AppCoordinator.swift` | Add `runQuickRefine()` mirroring `refineWithTone()`. |
| `app/Sources/LingoPulseApp/MenuBarController.swift` | Route `.quickRefine` from the menu callback to `runQuickRefine()`. |
| `app/Sources/LingoPulseApp/Constants.swift` | Add `quickRefineAppName = "QuickRefine"` constant for history rows. |

## New files

- `app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift`
- `app/Sources/LingoPulseApp/Commands/QuickRefineCommand.swift`
- `app/Tests/LingoPulseAppTests/QuickRefineCommandTests.swift`

## Refine-path notes

- `app: "QuickRefine"` is passed to `Fixer.refine(...)` so history rows are filterable. `Prompts.tone(forApp:selection:config:)` falls through to the default tone resolution since no per-app override exists for that name.
- `Fixer.alreadyRefined()` is left enabled — same dedupe semantics as Right-⌘ and Tone.
- A ring entry is appended on success exactly as today. The PreviewPanel reject path already pops it via `fixer.ring.popLatest()`.

## Edge cases

- **Empty/whitespace input** → close capture panel silently; do not chain to tone picker or refine.
- **Capture cancelled (Esc / outside click)** → no tone picker, no refine, no ring write.
- **Tone picker cancelled** → no refine call.
- **Ollama error or timeout** → existing `Notifications.show(...)` from the command surfaces it; no panel chain hangs.
- **Source app activation** — capture, tone picker, and preview each save and restore `previousApp` on close. Three sequential restores are fine: `NSApp.activate()` is idempotent and the source app stays focused, which is what `⌘V` after the chain needs.
- **Already-refined dedupe hit** → `Fixer` short-circuits and `Fixer.refine` returns; `QuickRefineCommand` shows a toast ("No change needed") and skips the preview. Same pattern as `ToneCommand`.

## Error handling

`QuickRefineCommand.execute` catches the same set as `PreviewCommand`:

- `FixerError.emptySelection` → silent (already filtered before the call, but defensive).
- `FixerError.ollama(.busy)` → log and return.
- `FixerError.ollama(.timeout)` → notification.
- other → notification with the error.

## Testing

`QuickRefineCommandTests` — unit tests with stubbed dependencies. Reuse the project's existing `Fixer` test seam (a real `Fixer` with a mocked `OllamaService`, the pattern used in current command tests).

Cases:

1. Empty input → no refine call, no preview, no ring write.
2. Capture cancelled → no refine call.
3. Tone cancelled → no refine call.
4. Happy path → refine called once with `app == "QuickRefine"` and the chosen tone override; PreviewPanel invocation captured.
5. Ollama timeout → notify hook called, no preview shown, no exception leaked.
6. Reject path → ring's latest entry popped after preview reject.

UI smoke tests are not in scope — the project has no UI test infrastructure.

## Out of scope

- New global hotkey or trigger configuration.
- Settings panel changes (no "Default tone for Quick Refine" preference, no per-app overrides).
- Draft persistence between invocations.
- Auto-paste back into the source app.
- Top-level menu-bar item.
- Streaming tokens into the capture panel (refine result still goes to PreviewPanel as a finished string).

## Open questions

None at design time. Implementation plan can proceed.
