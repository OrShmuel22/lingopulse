# LingoPulse IME — Compatibility Matrix

Status values: **Pass** | **Partial** | **Fail** | **Untested**

Partial = IME receives keystrokes but acceptance/replacement has issues (e.g. clipboard fallback needed, cursor drift, chip appears but Tab doesn't commit).

Last updated: _fill in date when you test_

---

## Legend

| Column | Meaning |
|--------|---------|
| Keystroke capture | IME receives characters via `inputText(_:client:)` |
| Chip appears | Suggestion window shows after debounce |
| Tab accepts | Tab key commits the edit and replaces text |
| Esc dismisses | Escape key dismisses chip without change |
| Replacement accurate | Replaced text is exactly the typed buffer, no extra chars |
| Cursor position | Cursor ends at correct position after accept |

---

## Native Cocoa apps (NSTextView)

| App | Keystroke capture | Chip appears | Tab accepts | Esc dismisses | Replacement accurate | Cursor position | Notes |
|-----|:-----------------:|:------------:|:-----------:|:-------------:|:--------------------:|:---------------:|-------|
| TextEdit | Untested | Untested | Untested | Untested | Untested | Untested | |
| Notes | Untested | Untested | Untested | Untested | Untested | Untested | |
| Mail (compose window) | Untested | Untested | Untested | Untested | Untested | Untested | |
| Pages | Untested | Untested | Untested | Untested | Untested | Untested | |
| Xcode (editor pane) | Untested | Untested | Untested | Untested | Untested | Untested | Tab may trigger autocomplete first |

Sample text for Cocoa apps:
```
teh quick brown fox jumpped over teh lazy dog. there going to there office tomorow.
```

---

## Electron apps

| App | Keystroke capture | Chip appears | Tab accepts | Esc dismisses | Replacement accurate | Cursor position | Notes |
|-----|:-----------------:|:------------:|:-----------:|:-------------:|:--------------------:|:---------------:|-------|
| Slack | Untested | Untested | Untested | Untested | Untested | Untested | Electron; AX writes may need clipboard fallback |
| Notion | Untested | Untested | Untested | Untested | Untested | Untested | Electron |
| VS Code | Untested | Untested | Untested | Untested | Untested | Untested | Electron; Tab likely hijacked by editor |
| Linear | Untested | Untested | Untested | Untested | Untested | Untested | Electron |
| Discord | Untested | Untested | Untested | Untested | Untested | Untested | Electron |

Sample text for Electron apps:
```
hey can u review this pr? i think its missing a few edge cases, should of added tests earlier
```

---

## Web browsers (input fields)

| App | Surface | Keystroke capture | Chip appears | Tab accepts | Esc dismisses | Replacement accurate | Notes |
|-----|---------|:-----------------:|:------------:|:-----------:|:-------------:|:--------------------:|-------|
| Safari | address bar | Untested | Untested | Untested | Untested | Untested | |
| Safari | `<textarea>` (e.g. Gmail compose) | Untested | Untested | Untested | Untested | Untested | |
| Safari | `contenteditable` (e.g. Notion web) | Untested | Untested | Untested | Untested | Untested | |
| Chrome | `<textarea>` | Untested | Untested | Untested | Untested | Untested | |
| Chrome | `contenteditable` | Untested | Untested | Untested | Untested | Untested | |
| Firefox | `<textarea>` | Untested | Untested | Untested | Untested | Untested | Firefox has non-standard IME handling |

Sample text for browser inputs:
```
Im writing this email to folowup on are previous conversation. Their should be a solution avaliable.
```

---

## Terminals (expected: excluded)

These are in the default exclusion list and should never show chips.

| App | Excluded by default | No chip appears | Notes |
|-----|:-------------------:|:---------------:|-------|
| Terminal.app | Yes | Untested | Should be auto-excluded |
| iTerm2 | Yes | Untested | Should be auto-excluded |
| Warp | Yes | Untested | Should be auto-excluded |
| Alacritty | Yes | Untested | Should be auto-excluded |

---

## Other apps

| App | Keystroke capture | Chip appears | Tab accepts | Esc dismisses | Replacement accurate | Notes |
|-----|:-----------------:|:------------:|:-----------:|:-------------:|:--------------------:|-------|
| Superhuman | Untested | Untested | Untested | Untested | Untested | |
| Figma (text layer) | Untested | Untested | Untested | Untested | Untested | Web wrapper |
| Bear | Untested | Untested | Untested | Untested | Untested | Native Cocoa |
| Obsidian | Untested | Untested | Untested | Untested | Untested | Electron |
| Things 3 | Untested | Untested | Untested | Untested | Untested | Native Cocoa |

Sample text for other apps:
```
This is a test sentance with some typos and grammer issues that lingopulse should fix automaticaly.
```

---

## Diagnostic log output

When LingoPulseIME starts, it logs app activation events. Look for lines like:

```
LingoPulseIME [AppDiag]: active app: Slack (com.tinyspeck.slackmacgap) | activationPolicy: regular | IME input likely: YES
LingoPulseIME [AppDiag]: active app: iTerm2 (com.googlecode.iterm2) | activationPolicy: regular | IME input likely: NO (excluded)
LingoPulseIME [AppDiag]: active app: Finder (com.apple.finder) | activationPolicy: regular | IME input likely: NO (accessory/prohibited)
```

To tail these logs:
```bash
log stream --predicate 'eventMessage CONTAINS "LingoPulseIME"' --level debug
```

---

## How to update this file

After testing each surface, replace `Untested` with one of:
- **Pass** — works exactly as expected
- **Partial** — see Notes column for what broke
- **Fail** — IME does not function in this surface
