---
title: Fixer — App Compatibility Matrix
status: STUB — fill after manual QA pass
created: 2026-04-24
updated: 2026-04-24
---

> Status: STUB — fill after manual QA pass

# Fixer — App Compatibility Matrix

Does Refine + Undo + Preview + Tone picker + Dictionary work correctly in each target app?

| App                 | ⌘⌥E Refine | ⌘⌥Z Undo | ⌘⌥⇧E Preview | ⌘⌥T Tone | ⌘⌥S Dictionary | Notes |
|---------------------|------------|----------|---------------|----------|----------------|-------|
| Slack desktop       | ?          | ?        | ?             | ?        | ?              |       |
| Slack web           | ?          | ?        | ?             | ?        | ?              |       |
| Apple Mail          | ?          | ?        | ?             | ?        | ?              |       |
| Gmail web           | ?          | ?        | ?             | ?        | ?              |       |
| Cursor (editor)     | ?          | ?        | ?             | ?        | ?              |       |
| Cursor (AI chat)    | ?          | ?        | ?             | ?        | ?              |       |
| VS Code             | ?          | ?        | ?             | ?        | ?              |       |
| Notes               | ?          | ?        | ?             | ?        | ?              |       |
| Messages            | ?          | ?        | ?             | ?        | ?              |       |
| Discord             | ?          | ?        | ?             | ?        | ?              |       |
| Linear (web/app)    | ?          | ?        | ?             | ?        | ?              |       |
| Terminal / iTerm2   | ?          | ?        | ?             | ?        | ?              |       |

Legend: ✅ pass • ⚠️ partial • ❌ fail • ? untested

Any ❌ gets a row in Notes describing the failure and any fallback. Accessibility-API-based text injection (Cmd+V via osascript) fails in some Electron apps; document alternatives there.
