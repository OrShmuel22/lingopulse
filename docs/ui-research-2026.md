# LingoPulse UI Research — 2026 Expert Audit & Redesign Plan

**Author:** Internal design audit
**Date:** 2026-04-28
**Scope:** All user-facing UI surfaces in LingoPulse (menu bar, panels, overlays, settings, onboarding)
**Goal:** Bring the app up to a professional 2026 macOS bar — visually (Liquid Glass), behaviorally (Raycast-class keyboard-first speed), and ergonomically (Grammarly-class inline diff agency).

---

## 1. Industry Reference Frame (April 2026)

Three reference points dominate the macOS-native AI-writing space right now:

| Reference | What it does well | What we should steal |
|-----------|-------------------|----------------------|
| **macOS 26 Tahoe (Liquid Glass)** | Translucent, refractive material with content-aware tinting; transparent menu bar; toolbars/popovers float as glass | Adopt `.regularMaterial` / `.thickMaterial` consistently, drop opaque dark fills, use `glassEffect()` API for chrome on macOS 26 |
| **Raycast** | Single command palette, fuzzy search, keyboard-first, every action has a shortcut hint, never makes you reach for the mouse | One unified palette instead of 4 separate panels; type-to-filter; numbered shortcuts visible on every row |
| **Apple Writing Tools / Grammarly** | Inline diff with accept/reject per change, ghost text overlay with no modal interruption, clear "AI starting point — you decide" framing | Inline diff (word-level) instead of side-by-side block compare; accept-all / reject-all + per-change controls |

**Sources** — [Apple Liquid Glass developer gallery (2026)](https://developer.apple.com/design/new-design-gallery-2026/) · [Liquid Glass best practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo) · [Raycast 2026 review](https://devtoolsreviewed.com/raycast-review/) · [Apple HIG 2026](https://developer.apple.com/design/human-interface-guidelines) · [Grammarly vs Apple Writing Tools (2025)](https://tidbits.com/2025/01/30/why-grammarly-beats-apples-writing-tools-for-serious-writers/)

---

## 2. Audit of Current Surfaces

| File | Surface | Status (2026 bar) | Headline issue |
|------|---------|-------------------|----------------|
| `MenuBarController.swift` | Status item + dropdown menu | **C** | Emoji titles (`✏️`, `⚠️`, `🚫`) — not template-rendered, look amateur on Liquid Glass menu bar |
| `Views/QuickActionPanel.swift` | Double-tap action menu | **C+** | Static 6-item grid, no fuzzy search, no live preview, no keyboard hints rendered properly |
| `Views/PreviewPanel.swift` | Refinement preview | **D** | Side-by-side blocks; no diff highlight; titled window with chrome — too heavy for a 2-second decision |
| `Views/TonePickerPanel.swift` | Tone picker | **D** | Plain List; no fuzzy filter; no preview of what each tone produces; ignores the user's selection |
| `Views/DictionaryPanel.swift` | Dictionary candidates | **C** | Decent list, but uses titled NSWindow — should be a glass popover anchored to caret |
| `Views/GhostOverlayWindow.swift` | Live-mode suggestion | **B** | Already material-based; missing inline diff, hard-coded 8s timeout, no progressive disclosure |
| `Views/UndoFallbackPanel.swift` | Undo fallback | unknown | Likely same modal-window pattern — needs same glass + caret-anchored treatment |
| `OnboardingWindow.swift` | First-run flow | **B** | Decent 3-step, accessibility detection good. Could use Liquid Glass nav, animated state transitions |
| `SettingsWindow.swift` | Preferences (6 tabs) | **C** | Tab count is high (General / Triggers / Apps / Advanced / Models & Prompts / Live Mode); deep settings buried; no search |

The single highest-leverage problems:

1. **Multiple panel styles, none consistent.** PreviewPanel and TonePickerPanel use titled `NSWindow`s; QuickActionPanel uses a borderless `NSPanel` with `VisualEffectBackground`; GhostOverlayWindow uses `.nonactivatingPanel`. Five different design decisions, no design language.
2. **No inline diff anywhere.** Preview shows two boxes — user has to scan both and figure out what changed. Grammarly and Apple Writing Tools both do per-token diffs as table stakes.
3. **No fuzzy command palette.** Quick Action panel is the closest thing, but it is a static menu, not a search-driven palette. Tone picker, dictionary, and quick action should be the *same* surface.
4. **Settings has 6 tabs.** Industry trend is sidebar + search (the new System Settings pattern).
5. **Emoji menu bar icon.** Doesn't render correctly with the Liquid Glass transparent menu bar; competing apps use SF Symbols template images.

---

## 3. Design Language Decision

Adopt a single design language, applied uniformly:

### 3.1 Material & Chrome
- **One panel style.** All transient surfaces (action menu, preview, tone, dictionary, undo, ghost) use the same recipe:
  - `NSPanel` with `[.borderless, .nonactivatingPanel, .fullSizeContentView]`.
  - SwiftUI background = `.regularMaterial` on macOS 14–25, `.glassEffect()` on macOS 26+ (gated by `#available`).
  - Corner radius **14pt** (matches macOS 26 system popovers).
  - Shadow: system default (`hasShadow = true`).
  - Outline: 0.5pt stroke at `Color.primary.opacity(0.08)` for definition on busy backgrounds.
- **Anchored to caret, not centered.** Every transient panel positions near the user's cursor (already done in QuickActionPanel via `CaretLocator`; extend to Preview, Tone, Dictionary).
- **Drop titled windows for transient flows.** Preview, Tone, and Dictionary panels become borderless glass popovers — title bars are reserved for Settings and Onboarding only.

### 3.2 Typography
- System font, semantic weights only. Title3 + bold for primary labels, callout for body, caption for hints.
- **No emoji in chrome.** Replace menu bar emojis with SF Symbols template images:
  - Idle → `text.bubble`
  - Refining → animated spinner or `arrow.triangle.2.circlepath` with rotation
  - AX revoked → `exclamationmark.shield`
  - Daemon down → `bolt.slash`

### 3.3 Color
- Accent uses system tint (respects user's macOS accent color).
- Diff colors are semantic, not literal red/green:
  - Insertion: `.green.opacity(0.18)` background, `.green.mix(with: .primary, by: 0.5)` text on light, full text on dark.
  - Deletion: `.red.opacity(0.18)` with strikethrough, secondary foreground.
- **Test in dark mode.** All current panels assume light background.

### 3.4 Motion
- Spring animation `(response: 0.28, dampingFraction: 0.85)` for panel show/hide.
- Material fade, not opacity fade (matches Liquid Glass appearance physics).
- Highlight transitions on quick-action rows: 120ms ease-in-out.

---

## 4. Core UX Reshape

### 4.1 Unify into a Command Palette

Today the user has three different keyboard-driven surfaces:
- Right ⌘ → refine immediately (no UI).
- Double-tap ⇧ → 6-item action menu.
- Selecting tone → secondary `TonePickerPanel`.

In 2026 the expected pattern is a **single command palette** (Raycast model). One trigger surface, type to filter, every command always reachable.

**Proposed single-surface flow:**

```
[double-tap ⇧]                             ┌──────────────────────────────────┐
    │                                       │ 🔍 Type a command…               │
    └──> Glass popover anchored at caret    ├──────────────────────────────────┤
                                            │ ✨ Refine                    1   │
                                            │ 👁  Preview                  2   │
                                            │ 🎨 Tone…                    3   │
                                            │ ↩  Undo                     4   │
                                            │ 📖 Find a Word              5   │
                                            │ 📥 Capture Style            6   │
                                            │  ───── Recents ─────              │
                                            │ 🎨 Tone → Friendly           ⏎  │
                                            └──────────────────────────────────┘
```

- **Live filter.** As user types, list narrows. Empty input shows the canonical 6 commands plus a "Recents" section.
- **Submenu in place.** Picking "Tone…" replaces the list with tone options *in the same panel* (no second window). Esc steps back one level.
- **Per-row keyboard hint** rendered as a small kbd-style chip on the right (already partially done in `QuickActionPanel`, just needs polish).
- **Action preview on hover/highlight.** When a command is highlighted for >250ms, show a 1-line description below the search box ("Refine the selection in place — preserves formatting").

This eliminates `TonePickerPanel.swift` and `DictionaryPanel.swift` as standalone windows; they become *modes* of the unified palette.

### 4.2 Inline Diff Preview (replace `PreviewPanel`)

Today: side-by-side box comparison. User has to read both, find the differences, decide.

Future (Grammarly-class): **inline word-level diff with per-change controls.**

```
┌─ Preview Refinement ─────────────────────────────────────┐
│                                                            │
│  I ~~was wondering if maybe~~ would like to know whether   │
│      ───────────────────────                                │
│      removed                                                │
│                                                            │
│  the meeting ~~has been~~ was rescheduled.                  │
│                ──────────                                   │
│                changed → "was"                              │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Reject  ⎋    Reject this change  ←    Accept All  ⏎ │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

- Render as a `Text` with attributed runs. Use `AttributedString` with semantic styling (insert/delete) — readable in both light/dark modes.
- **Per-change navigation:** ← / → arrows step through changes; Space = toggle accept/reject for the current change.
- **Bottom bar keyboard hints always visible.** Esc / ⏎ / arrow keys.
- **Diff library:** use Apple's built-in `CollectionDifference` on tokenized words — no extra dependency.

### 4.3 Ghost Overlay (Live Mode) — Progressive Disclosure

Current `GhostOverlayWindow` shows the full refined sentence and forces a binary Apply/Dismiss decision in 8s.

Better: progressive disclosure aligned with Apple Intelligence's overlay pattern.

- **Collapsed state (default):** Pill near caret showing only "✨ Suggestion ↹" — minimal visual cost.
- **Expanded state:** Pressing Tab (configurable) expands to show the inline-diff with Apply/Dismiss.
- **No fixed timeout.** Dismiss when user types 3+ characters elsewhere (already debounced — easy hook), or moves caret >2 lines away. The hard 8s timeout is hostile when reading carefully.
- **Accept-with-edit.** Clicking the pill should drop the suggestion into a small editable buffer, not auto-apply. Lets users tweak before commit (the Apple HIG 2026 "starting point, not finished product" principle).

### 4.4 Status Item

- Drop emoji titles. Use SF Symbol template images via `NSStatusItem.button.image`.
- Refining state: rotating `arrow.triangle.2.circlepath` via `CABasicAnimation` instead of swapping ⏳/⌛️ text frames.
- Add a **mini-popover dashboard** (like Tailscale, Magnet, Tot do): clicking the icon opens a small popover with:
  - Last refinement (1 line, click to copy/restore)
  - Toggle: Live Mode
  - Toggle: Excluded for current app
  - Open Settings, Quit
- Right-click keeps the current full menu for power users.

### 4.5 Settings Redesign

Current: 6-tab `TabView`. The 2026 macOS pattern is **System-Settings-style sidebar + search**.

```
┌─ LingoPulse Settings ─────────────────────────────────────┐
│  🔍 Search…             │                                   │
│                         │   General                          │
│  ✦ General              │   ─────────                        │
│  ⌨  Triggers            │   ☐ Enabled (live suggestions)     │
│  🪟 Apps & Exclusions   │   ☐ Launch at login                │
│  ⚡ Live Mode           │   ☐ Show menu bar dashboard        │
│  🧠 Models & Prompts    │                                    │
│  🔧 Advanced            │   Theme: ◉ System ○ Light ○ Dark   │
│  ─────                  │                                    │
│  📊 Stats               │                                    │
│  ℹ️  About               │                                    │
└─────────────────────────────────────────────────────────────┘
```

- **Sidebar, not tabs.** Use SwiftUI `NavigationSplitView`. Easier to grow.
- **Search field at top of sidebar.** Filters settings by label (matches macOS System Settings behavior since macOS 13).
- **Merge "Apps" and "Live Mode → Excluded Apps".** Both are exclusion lists; one screen with a segmented toggle (Triggers / Live).
- **Add Stats.** Most pro AI apps surface usage: refinements this week, average latency, top tones used, model tokens/sec measured. We already have benchmark data — surface it.
- **Inline help.** Replace the "..." captions with `Help` buttons that open a small popover explaining the setting (HIG 2026 pattern).

### 4.6 Onboarding Polish

The onboarding is already 80% there. Specific upgrades:

- **Replace step circles with a horizontal progress bar.** Three circles is fine for 3 steps but doesn't convey progress; a thin progress bar reads as "this is short."
- **Animated illustration on welcome.** A single `CABasicAnimation` on the icon (subtle scale/rotate, 2s loop) conveys life without being noisy.
- **Add Step 0.5: model picker.** Right now the user discovers in Settings that they can pick fixer model. Surface it during onboarding with the measured Hebrew/English model recommendations from the benchmarks. Defaults are fine, but showing the choice exists builds trust.
- **Final step: CTA to try it.** Instead of "Finish," button reads "Try it now" — opens a small text field, lets user type a sentence, demonstrates a refinement live. Ship-quality apps end onboarding with a successful first action, not a button.

---

## 5. Concrete File-Level Plan

This section maps each recommendation to the file(s) that change. The goal is to make this implementable as a series of small PRs, not a big-bang rewrite.

| PR | Files | Effort | Risk |
|----|-------|--------|------|
| 1. Design tokens module (`Sources/LingoPulseApp/UI/DesignTokens.swift`) — corner radius, materials, animations, panel factory | new file | S | Low |
| 2. Migrate `QuickActionPanel` to use design tokens + add type-to-filter | `Views/QuickActionPanel.swift` | M | Low |
| 3. Replace `PreviewPanel` titled window with anchored glass panel + inline diff | `Views/PreviewPanel.swift` + new `Views/InlineDiffView.swift` | L | Medium |
| 4. Fold `TonePickerPanel` and `DictionaryPanel` into `QuickActionPanel` as submodes | delete two files, extend one | M | Medium |
| 5. SF Symbol status item + spinning animation | `MenuBarController.swift` | S | Low |
| 6. Status item popover dashboard | `MenuBarController.swift` + new `Views/StatusDashboardView.swift` | M | Low |
| 7. Settings sidebar refactor | `SettingsWindow.swift` | M | Low |
| 8. Settings search | `SettingsWindow.swift` | S | Low |
| 9. Stats tab (read existing history/benchmark data) | new tab + reads from `HistoryStore` | M | Low |
| 10. Ghost overlay: collapsed/expanded states + remove hard timeout | `Views/GhostOverlayWindow.swift` | M | Medium |
| 11. Onboarding: progress bar + Try-it step | `OnboardingWindow.swift` | M | Low |
| 12. Liquid Glass `glassEffect()` gated by `#available(macOS 26, *)` | DesignTokens.swift | S | Low |

**Total estimate:** ~3 weeks of focused frontend work, broken into 12 PRs. Order PRs 1, 2, 5, 7, 8 first — they unlock the rest with no user-visible regression risk.

---

## 6. Non-Goals (Explicitly Deferred)

To keep scope honest:

- **No iPad/iPhone version.** macOS only.
- **No theming engine.** System accent + light/dark is enough.
- **No marketing site / icon redesign.** Out of scope for in-app UX.
- **No localization.** Hebrew support stays at the model layer (per existing memory); UI strings stay English for now.
- **No full visionOS port.** Liquid Glass borrows from visionOS, but we don't need spatial UI.

---

## 7. Success Metrics

How we know the redesign worked:

| Metric | Today (estimated) | Target |
|--------|-------------------|--------|
| Time-to-first-refinement after install | ~2 min (read onboarding, find shortcut) | <30s (try-it step) |
| Mouse interactions per refinement | 1–2 (close panels, click accept) | 0 (full keyboard) |
| Settings-tab discoverability for "Models & Prompts" | low (5th tab) | searchable, sidebar |
| Misfires of double-tap shift per day | unmeasured (user reports "all the time") | <1 (mouse-dirty fix already shipped, monitor) |
| Visual consistency across 6 panel surfaces | 5 different styles | 1 design language |

---

## 8. Open Questions

1. **Liquid Glass minimum target.** Do we drop macOS 13/14 support to ship a uniform glass look, or gate `glassEffect()` behind `#available(macOS 26, *)` and accept two looks for now? **Recommendation:** gate, don't drop.
2. **Command palette extensibility.** Do we want third-party commands (Raycast-style extensions) eventually? If yes, design the palette's data model with that in mind from PR 2.
3. **Stats panel privacy.** History data is local — fine to surface aggregates. But do we surface *content* (last refinement preview)? **Recommendation:** show last 5 refinements with "Hide content" toggle defaulting on for screen-sharing safety.
4. **Right-⌘ keeps no-UI behavior?** Power users may want a 1-second toast on refine ("Refined ✓"). Optional, off by default.

---

## 9. References

- [Apple Liquid Glass developer gallery (2026)](https://developer.apple.com/design/new-design-gallery-2026/)
- [Liquid Glass best practices for SwiftUI (Apr 2026)](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [LogRocket — adopting Liquid Glass](https://blog.logrocket.com/ux-design/adopting-liquid-glass-examples-best-practices/)
- [Apple Human Interface Guidelines (2026)](https://developer.apple.com/design/human-interface-guidelines)
- [Building macOS menu bar apps with SwiftUI (2026 update)](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [Raycast 2026 review — keyboard-first launcher](https://devtoolsreviewed.com/raycast-review/)
- [Grammarly vs Apple Writing Tools — UX comparison](https://tidbits.com/2025/01/30/why-grammarly-beats-apples-writing-tools-for-serious-writers/)
- [Michael Tsai — Grammarly vs. Apple Writing Tools](https://mjtsai.com/blog/2025/02/17/grammarly-vs-apples-writing-tools/)
