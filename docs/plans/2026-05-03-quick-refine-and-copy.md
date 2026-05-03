# Quick Refine & Copy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Quick Refine" entry to the existing double-tap-Shift Quick Action menu that opens a typed-input scratchpad, runs the existing tone picker → Fixer → PreviewPanel chain with `axWriteAvailable: false`, so the refined text auto-copies to the clipboard for paste into terminals like Claude Code.

**Architecture:** Pure composition over existing components. One new view (`QuickRefineCapturePanel`), one new command (`QuickRefineCommand`), one new enum case (`QuickAction.quickRefine`), one new constant. No changes to `Fixer`, `Prompts`, `OllamaService`, `RingBuffer`, `HistoryStore`. Reference design: `docs/plans/2026-05-03-quick-refine-and-copy-design.md`.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, swift-testing (`Testing` framework, `@Suite` / `@Test` / `#expect`).

---

## Conventions for this plan

- All `swift test` and `swift build` commands run from `/Users/or.shmuel/Code/personal/lingopulse/app/` (the `Package.swift` lives there).
- Commit messages use Conventional Commits — no Jira prefix (this is a personal project; the `.git/hooks/commit-msg` requires Jira but should be bypassed with `--no-verify` for every commit in this plan).
- The existing test framework is swift-testing, not XCTest. Tests look like `@Test func name() { #expect(...) }` inside a `@Suite struct`.
- Follow existing code style: K&R braces, no `Async` suffix, descriptive names, no comments unless explaining *why*.

---

## Task 1: Add `.quickRefine` enum case + test changes

**Files:**
- Modify: `app/Sources/LingoPulseApp/Views/QuickActionPanel.swift:4-27` (enum), `:138` (digit guard)
- Modify: `app/Tests/LingoPulseAppTests/QuickActionPanelTests.swift`

**Step 1: Update the failing tests first**

Edit `app/Tests/LingoPulseAppTests/QuickActionPanelTests.swift`:

```swift
@Test func allCasesCountIsFive() {
    #expect(QuickAction.allCases.count == 5)
}
```

Replace the existing `allCasesCountIsFour` test with this. Also update `rawValueInitForValidRange` and `rawValueInitForOutOfRange`:

```swift
@Test func rawValueInitForValidRange() {
    #expect(QuickAction(rawValue: 1) == .preview)
    #expect(QuickAction(rawValue: 2) == .refine)
    #expect(QuickAction(rawValue: 3) == .tone)
    #expect(QuickAction(rawValue: 4) == .quickRefine)
    #expect(QuickAction(rawValue: 5) == .undo)
}

@Test func rawValueInitForOutOfRange() {
    #expect(QuickAction(rawValue: 0) == nil)
    #expect(QuickAction(rawValue: 6) == nil)
}
```

Update `moveDownWraps`:

```swift
@Test func moveDownWraps() {
    let vm = QuickActionPanelViewModel()
    for _ in 0..<5 { vm.moveDown() }
    #expect(vm.highlightedIndex == 0)
}
```

`moveDownAdvances` already covers `.refine` then `.tone` — leave as-is.

**Step 2: Run tests to verify they fail**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift test --filter QuickActionTests 2>&1 | tail -20
```

Expected: build error (case `.quickRefine` does not exist) or test failures.

**Step 3: Update the enum**

Edit `app/Sources/LingoPulseApp/Views/QuickActionPanel.swift:4-27`:

```swift
enum QuickAction: Int, CaseIterable, Identifiable {
    case preview = 1, refine, tone, quickRefine, undo
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .refine:      return "Refine"
        case .preview:     return "Preview"
        case .tone:        return "Tone"
        case .quickRefine: return "Quick Refine"
        case .undo:        return "Undo"
        }
    }

    var systemImage: String {
        switch self {
        case .refine:      return "wand.and.stars"
        case .preview:     return "eye"
        case .tone:        return "paintpalette.fill"
        case .quickRefine: return "square.and.pencil"
        case .undo:        return "arrow.uturn.backward"
        }
    }

    var shortcutHint: String { String(rawValue) }
}
```

**Step 4: Widen digit guard**

Edit `app/Sources/LingoPulseApp/Views/QuickActionPanel.swift:138`:

```swift
if let digit = chars.first.flatMap({ Int(String($0)) }),
   digit >= 1 && digit <= 5,
   let action = QuickAction(rawValue: digit) {
    fire(action)
    return nil
}
```

**Step 5: Bump panel height to fit five rows**

Edit `app/Sources/LingoPulseApp/Views/QuickActionPanel.swift:58`:

```swift
hc.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
```

And the matching `.frame(...)` in `QuickActionView.body` (around line 220):

```swift
.frame(width: 240, height: 240)
```

**Step 6: Run tests to verify they pass**

```bash
swift test --filter QuickActionTests 2>&1 | tail -20
```

Expected: PASS.

**Step 7: Build the app to catch compile errors elsewhere (e.g., `AppDelegate`'s `switch` on `QuickAction`)**

```bash
swift build 2>&1 | tail -20
```

Expected: error in `AppDelegate.swift:144-149` — switch must be exhaustive. **Don't fix it yet** — that's Task 7. For now, add `case .quickRefine: break` as a temporary placeholder so the project builds:

Edit `app/Sources/LingoPulseApp/AppDelegate.swift:144-149`:

```swift
switch action {
case .refine:      coordinator.refineFocusedSelection()
case .preview:     coordinator.previewSelection()
case .tone:        coordinator.refineWithTone()
case .quickRefine: break  // wired in Task 7
case .undo:        coordinator.undoLast()
}
```

```bash
swift build 2>&1 | tail -10
```

Expected: PASS.

**Step 8: Commit**

```bash
git add app/Sources/LingoPulseApp/Views/QuickActionPanel.swift \
        app/Sources/LingoPulseApp/AppDelegate.swift \
        app/Tests/LingoPulseAppTests/QuickActionPanelTests.swift
git commit --no-verify -m "feat(quickaction): add .quickRefine enum case and menu row"
```

---

## Task 2: Add `quickRefineAppName` constant

**Files:**
- Modify: `app/Sources/LingoPulseApp/Constants.swift`

**Step 1: Add a new nested enum**

Edit `app/Sources/LingoPulseApp/Constants.swift`, append inside `enum Constants`:

```swift
enum AppNames {
    static let quickRefine = "QuickRefine"
}
```

**Step 2: Build to confirm**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift build 2>&1 | tail -5
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/Sources/LingoPulseApp/Constants.swift
git commit --no-verify -m "feat(constants): add Constants.AppNames.quickRefine"
```

---

## Task 3: Create `QuickRefineCapturePanel` view skeleton

**Files:**
- Create: `app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift`

**Step 1: Write a smoke test first**

Create `app/Tests/LingoPulseAppTests/QuickRefineCapturePanelTests.swift`:

```swift
import Testing
import AppKit
@testable import LingoPulseApp

@Suite @MainActor struct QuickRefineCapturePanelSmokeTests {

    @Test func constructShowCloseSmokeNoCrash() async {
        let panel = QuickRefineCapturePanel()
        panel.show(onPick: { _ in })
        panel.close()
    }

    @Test func closeWithoutShowIsNoOp() async {
        let panel = QuickRefineCapturePanel()
        panel.close()
    }
}
```

**Step 2: Run to confirm it fails**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift test --filter QuickRefineCapturePanelSmokeTests 2>&1 | tail -10
```

Expected: build error — `QuickRefineCapturePanel` does not exist.

**Step 3: Create the panel file**

Create `app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift`. Mirror `TonePickerPanel` lifecycle exactly (self-retain, local + global monitors, restore previous app):

```swift
import AppKit
import SwiftUI

private final class KeyableCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickRefineCapturePanel {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var onPick: ((String?) -> Void)?
    private var previousApp: NSRunningApplication?
    private var selfReference: QuickRefineCapturePanel?
    private var textBinding: TextBinding?

    func show(onPick: @escaping (String?) -> Void) {
        if panel != nil { return }
        self.onPick = onPick
        self.previousApp = NSWorkspace.shared.frontmostApplication

        let binding = TextBinding()
        self.textBinding = binding

        let view = QuickRefineCaptureView(
            binding: binding,
            onSubmit: { [weak self] in self?.fire() },
            onCancel: { [weak self] in self?.cancel() }
        )

        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 520, height: 220)

        let p = KeyableCapturePanel(
            contentRect: hc.view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hc
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.center()

        self.panel = p
        self.selfReference = self
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        cancel()
    }

    private func cancel() {
        guard panel != nil else { return }
        teardown()
        let cb = onPick
        onPick = nil
        cb?(nil)
        selfReference = nil
    }

    private func fire() {
        let text = (textBinding?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        let cb = onPick
        onPick = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            cb?(text.isEmpty ? nil : text)
        }
        selfReference = nil
    }

    private func teardown() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        textBinding = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }
}

@MainActor
final class TextBinding: ObservableObject {
    @Published var text: String = ""
}

private struct QuickRefineCaptureView: View {
    @ObservedObject var binding: TextBinding
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Refine — type or paste text")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $binding.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.10))
                    )
                HStack(spacing: 12) {
                    ShortcutHint(key: "↩", label: "Refine")
                    ShortcutHint(key: "⇧↩", label: "Newline")
                    Spacer()
                    ShortcutHint(key: "Esc", label: "Cancel")
                }
                .font(.caption)
            }
            .padding(14)
        }
        .frame(width: 520, height: 220)
    }
}

private struct ShortcutHint: View {
    let key: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.18))
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

Note: this skeleton has **no key handling yet** — Enter/Shift+Enter/Esc are wired in Task 4. The smoke tests only verify construction/show/close.

**Step 4: Run tests to verify they pass**

```bash
swift test --filter QuickRefineCapturePanelSmokeTests 2>&1 | tail -10
```

Expected: PASS.

**Step 5: Commit**

```bash
git add app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift \
        app/Tests/LingoPulseAppTests/QuickRefineCapturePanelTests.swift
git commit --no-verify -m "feat(quickrefine): add capture panel skeleton (no key handling yet)"
```

---

## Task 4: Wire key handling into capture panel

**Files:**
- Modify: `app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift` (add monitors in `show`)

**Step 1: Add monitors at the end of `show(onPick:)`**

Insert before the closing `}` of `show(onPick:)` in `QuickRefineCapturePanel.swift`:

```swift
localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
    guard let self else { return event }
    return self.handleKey(event: event)
}
globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
    if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
}
let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
    Task { @MainActor in self?.cancel() }
}
```

**Step 2: Add `handleKey`**

Add this method to the class:

```swift
private func handleKey(event: NSEvent) -> NSEvent? {
    switch event.keyCode {
    case 36, 76: // Return / numpad Enter
        // Shift+Enter inserts newline — let the TextEditor handle it.
        if event.modifierFlags.contains(.shift) {
            return event
        }
        fire()
        return nil
    case 53: // Escape
        cancel()
        return nil
    default:
        return event
    }
}
```

**Step 3: Run tests to verify nothing broke**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift test --filter QuickRefineCapturePanelSmokeTests 2>&1 | tail -10
```

Expected: PASS.

**Step 4: Commit**

```bash
git add app/Sources/LingoPulseApp/Views/QuickRefineCapturePanel.swift
git commit --no-verify -m "feat(quickrefine): wire Enter / Shift+Enter / Esc handlers"
```

---

## Task 5: Create `QuickRefineCommand` (TDD with injectable deps)

**Files:**
- Create: `app/Sources/LingoPulseApp/Commands/QuickRefineCommand.swift`
- Create: `app/Tests/LingoPulseAppTests/QuickRefineCommandTests.swift`

**Step 1: Write failing tests**

Create `app/Tests/LingoPulseAppTests/QuickRefineCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import LingoPulseApp

@MainActor
private func makeFixer(ollamaResponse: String) -> Fixer {
    let session = makeMockSession(response: ollamaResponse)
    let ollama = OllamaService(session: session)
    let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
    let ring = RingBuffer(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickrefine-ring-\(UUID().uuidString).json"),
        size: 5
    )
    let history = HistoryStore(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickrefine-hist-\(UUID().uuidString).jsonl")
    )
    return Fixer(ollama: ollama, config: config, history: history, ring: ring)
}

private func makeMockSession(response: String) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixerMockURLProtocol.self]
    FixerMockURLProtocol.handler = { req in
        let url = req.url ?? URL(string: "http://127.0.0.1")!
        let httpResp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let json = ["response": response]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (httpResp, data)
    }
    return URLSession(configuration: config)
}

@Suite struct QuickRefineCommandTests {

    @Test @MainActor func emptyCaptureReturnsEarly() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var tonePickCalls = 0
        var previewCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { nil },
            tonePick: { tonePickCalls += 1; return "Neutral" },
            showPreview: { _, _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)
        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func whitespaceOnlyCaptureReturnsEarly() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var tonePickCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "   \n  " },
            tonePick: { tonePickCalls += 1; return "Neutral" },
            showPreview: { _, _, _ in }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func toneCancelledSkipsRefine() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var previewCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { nil },
            showPreview: { _, _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func happyPathRefinesAndShowsPreview() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")
        var previewArgs: FixerResult?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { "Grammar-only" },
            showPreview: { result, _, _ in previewArgs = result }
        )
        await cmd.execute()

        #expect(previewArgs?.refined == "Fix this typo.")
        #expect(previewArgs?.app == Constants.AppNames.quickRefine)
        let entries = try await fixer.ring.listAll()
        #expect(entries.count == 1)
    }

    @Test @MainActor func rejectCallbackPopsRingEntry() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")
        var capturedReject: (() -> Void)?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { "Grammar-only" },
            showPreview: { _, _, reject in capturedReject = reject }
        )
        await cmd.execute()

        let beforeReject = try await fixer.ring.listAll()
        #expect(beforeReject.count == 1)

        capturedReject?()
        // popLatest() runs in a Task; give it a tick.
        try await Task.sleep(for: .milliseconds(50))

        let afterReject = try await fixer.ring.listAll()
        #expect(afterReject.isEmpty)
    }
}
```

**Step 2: Run to confirm failure**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift test --filter QuickRefineCommandTests 2>&1 | tail -15
```

Expected: build error — `QuickRefineCommand` does not exist.

**Step 3: Implement the command**

Create `app/Sources/LingoPulseApp/Commands/QuickRefineCommand.swift`:

```swift
import AppKit

@MainActor
final class QuickRefineCommand {
    typealias Capture = @MainActor () async -> String?
    typealias TonePick = @MainActor () async -> String?
    typealias ShowPreview = @MainActor (FixerResult, @escaping () -> Void, @escaping () -> Void) async -> Void

    private let fixer: Fixer
    private let capture: Capture
    private let tonePick: TonePick
    private let showPreview: ShowPreview
    private let notify: (String, String) -> Void

    init(
        fixer: Fixer,
        capture: @escaping Capture = QuickRefineCommand.defaultCapture,
        tonePick: @escaping TonePick = QuickRefineCommand.defaultTonePick,
        showPreview: @escaping ShowPreview = QuickRefineCommand.defaultShowPreview,
        notify: @escaping (String, String) -> Void = { title, body in
            Notifications.show(title: title, body: body)
        }
    ) {
        self.fixer = fixer
        self.capture = capture
        self.tonePick = tonePick
        self.showPreview = showPreview
        self.notify = notify
    }

    func execute() async {
        guard let text = await capture() else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let tone = await tonePick() else { return }

        let result: FixerResult
        do {
            result = try await fixer.refine(
                selection: trimmed,
                app: Constants.AppNames.quickRefine,
                toneOverride: tone
            )
        } catch FixerError.ollama(.busy) {
            Log.info("ollama busy — try again in a moment")
            return
        } catch FixerError.ollama(.timeout) {
            notify("LingoPulse", "Refinement timed out. Model may be cold.")
            return
        } catch {
            Log.error("quick refine error: \(error)")
            notify("LingoPulse", "Refine failed: \(error)")
            return
        }

        await showPreview(
            result,
            { /* accept = no-op; preview already auto-copied refined text */ },
            { [weak fixer] in
                Task { _ = try? await fixer?.ring.popLatest() }
                Log.info("quick refine preview rejected — rolled back ring entry")
            }
        )
    }

    static func defaultCapture() async -> String? {
        await withCheckedContinuation { cont in
            let panel = QuickRefineCapturePanel()
            panel.show { text in
                cont.resume(returning: text)
            }
        }
    }

    static func defaultTonePick() async -> String? {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                await TonePickerPanel().show(
                    tones: ToneCommand.availableTones,
                    preselected: "Grammar-only"
                ) { picked in
                    cont.resume(returning: picked)
                }
            }
        }
    }

    static func defaultShowPreview(
        _ result: FixerResult,
        _ onAccept: @escaping () -> Void,
        _ onReject: @escaping () -> Void
    ) async {
        await PreviewPanel().show(
            original: result.original,
            refined: result.refined,
            axWriteAvailable: false,
            onAccept: onAccept,
            onReject: onReject
        )
    }
}
```

Note: `TonePickerPanel.show(...)` invokes the `onPick` callback only on selection — Esc/cancel calls `close()` which doesn't fire `onPick`. To handle cancellation, we need to update `defaultTonePick` to also resume on cancel. Inspect `TonePickerPanel.swift:81-93` — `close()` is silent. **Update `TonePickerPanel.show(...)` is out of scope; the workaround is to wrap with a continuation that times out, or extend the panel API.**

**Decision:** for this plan, extend `TonePickerPanel.show(...)` to take an optional `onCancel` callback. This is a minimal API addition.

**Step 4: Add `onCancel` parameter to `TonePickerPanel.show`**

Edit `app/Sources/LingoPulseApp/Views/TonePickerPanel.swift`:

Change the signature at line 27 to:

```swift
func show(tones: [String], preselected: String, onCancel: (() -> Void)? = nil, onPick: @escaping (String) -> Void) async {
```

In the body, replace line 31:

```swift
self.onCancel = { [weak self] in
    onCancel?()
    self?.close()
}
```

This wires through cancel-callbacks but keeps existing call sites compiling (`onCancel` defaults to `nil`).

Also fix the `close()` method (line 81) to actually call `onCancel`:

```swift
func close() {
    removeMonitors()
    panel?.orderOut(nil)
    panel = nil
    let cancel = onCancel
    onPick = nil
    onCancel = nil
    let prev = previousApp
    previousApp = nil
    prev?.activate()
    cancel?()
    selfReference = nil
}
```

(The original `_ = cancel` at line 91 was dead — this fixes that too.)

**Step 5: Update `defaultTonePick` to use the new cancel hook**

In `QuickRefineCommand.swift`:

```swift
static func defaultTonePick() async -> String? {
    await withCheckedContinuation { cont in
        Task { @MainActor in
            var resolved = false
            await TonePickerPanel().show(
                tones: ToneCommand.availableTones,
                preselected: "Grammar-only",
                onCancel: {
                    if !resolved { resolved = true; cont.resume(returning: nil) }
                }
            ) { picked in
                if !resolved { resolved = true; cont.resume(returning: picked) }
            }
        }
    }
}
```

**Step 6: Run tests to verify they pass**

```bash
swift test --filter QuickRefineCommandTests 2>&1 | tail -20
```

Expected: all 5 tests PASS.

Also run the existing tone tests to verify the API change didn't break them:

```bash
swift test --filter ToneCommand 2>&1 | tail -10
swift build 2>&1 | tail -10
```

Expected: PASS, and build succeeds.

**Step 7: Commit**

```bash
git add app/Sources/LingoPulseApp/Commands/QuickRefineCommand.swift \
        app/Tests/LingoPulseAppTests/QuickRefineCommandTests.swift \
        app/Sources/LingoPulseApp/Views/TonePickerPanel.swift
git commit --no-verify -m "feat(quickrefine): add QuickRefineCommand with capture→tone→preview chain"
```

---

## Task 6: Wire `runQuickRefine` into `AppCoordinator`

**Files:**
- Modify: `app/Sources/LingoPulseApp/AppCoordinator.swift`

**Step 1: Add `runQuickRefine()` method**

Edit `app/Sources/LingoPulseApp/AppCoordinator.swift`, add after `refineWithTone()`:

```swift
func runQuickRefine() {
    let cmd = QuickRefineCommand(fixer: fixer)
    Task { @MainActor in await cmd.execute() }
}
```

**Step 2: Build to verify**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift build 2>&1 | tail -10
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/Sources/LingoPulseApp/AppCoordinator.swift
git commit --no-verify -m "feat(coordinator): add runQuickRefine() entry point"
```

---

## Task 7: Wire `.quickRefine` dispatch in `AppDelegate`

**Files:**
- Modify: `app/Sources/LingoPulseApp/AppDelegate.swift:144-149`

**Step 1: Replace the placeholder**

Edit `app/Sources/LingoPulseApp/AppDelegate.swift:144-149`:

```swift
switch action {
case .refine:      coordinator.refineFocusedSelection()
case .preview:     coordinator.previewSelection()
case .tone:        coordinator.refineWithTone()
case .quickRefine: coordinator.runQuickRefine()
case .undo:        coordinator.undoLast()
}
```

**Step 2: Build and run full test suite**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift build 2>&1 | tail -5
swift test 2>&1 | tail -20
```

Expected: build PASS, all tests PASS (including the existing 152 tests plus the new ones).

**Step 3: Commit**

```bash
git add app/Sources/LingoPulseApp/AppDelegate.swift
git commit --no-verify -m "feat(quickrefine): wire .quickRefine dispatch from quick action menu"
```

---

## Task 8: Manual smoke test

**Files:** none.

**Step 1: Build the bundle**

```bash
cd /Users/or.shmuel/Code/personal/lingopulse/app
swift build --configuration release 2>&1 | tail -5
./scripts/build-bundle.sh release 2>&1 | tail -5
```

Expected: `app/LingoPulse.app` is rebuilt.

**Step 2: Launch and verify the flow**

1. Quit any running LingoPulse.
2. `open ./LingoPulse.app`
3. Double-tap ⇧.
4. Confirm five rows appear: Preview · Refine · Tone · Quick Refine · Undo. Press `4`.
5. The capture panel should appear, focused. Type: `pls fixe this typoe`.
6. Press Enter — the tone picker should appear.
7. Press `5` (Grammar-only).
8. The PreviewPanel should appear with the diff, and the banner "Refined copied to clipboard — press Esc to dismiss, then ⌘V in your app." should be visible.
9. Press Esc.
10. Switch to Claude Code (or any terminal), press ⌘V — the refined text should paste.

**Step 3: Verify edge cases manually**

- Empty input: open capture, hit Enter with no text → panel closes, no chain.
- Capture cancel: open capture, hit Esc → panel closes silently.
- Tone cancel: capture → Enter → tone picker → Esc → no preview, no ring entry.
- Outside-click: open capture, click outside → panel closes silently.

**Step 4: Verify the audit log records the new app name**

```bash
tail -1 ~/.config/lingopulse/history.jsonl
```

Expected: the latest entry's `"app"` field reads `"QuickRefine"`.

**Step 5: No commit** — manual smoke is documentation only.

---

## Done

- New entry "Quick Refine" in the Quick Action menu, key `4`.
- Capture panel → tone picker → refine → PreviewPanel chain.
- Refined text auto-copies to clipboard on preview show.
- All 5 cancellation paths (capture-empty / capture-Esc / capture-outside / tone-Esc / preview-Esc) clean up correctly.
- History rows tagged `"QuickRefine"` for filtering.
- 5 new unit tests, all green.
- ~152 + new tests passing.

If the manual smoke test surfaces a UX issue (e.g., the auto-paste delay feels off, or the panel position is wrong on multi-monitor), file a follow-up — do **not** patch in this PR.
