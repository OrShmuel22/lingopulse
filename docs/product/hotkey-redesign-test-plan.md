# Hotkey Redesign — Manual Test Plan

Run these checks after merging the integration branch.

---

## 1. Single-key trigger — no selection

Open Slack and type a message without selecting any text.
Press Right ⌘ once (tap and release, do not hold).
Expected: The entire message in the compose box is refined in place.

## 2. Single-key trigger — with selection

Open Notes and type several sentences.
Highlight a single sentence.
Press Right ⌘ once.
Expected: Only the highlighted sentence is replaced with the refined version.

## 3. Double-tap trigger — quick-action panel appears

In any app (Slack, Notes, Chrome, etc.), double-tap ⇧ (two presses within ~300 ms, no other key between them).
Expected: A floating panel appears near the caret with six actions — Refine, Preview, Tone, Undo, Find a Word, Capture Style.

## 4. Quick-action panel — pick by number

After the panel appears (step 3), press the key "1".
Expected: Refine fires immediately; the panel closes.

Repeat with a selection visible; press "2".
Expected: Preview fires; panel closes.

## 5. Quick-action panel — Esc dismisses

Open the panel (double-tap ⇧).
Press Esc.
Expected: The panel closes with no action taken.

## 6. Shell integration — zsh

a. In Settings → Triggers, toggle "Enable shell bridge" ON.
b. Click "Install for zsh".
c. Expected: A dialog confirms lines were added to ~/.zshrc.
d. In iTerm (or Terminal), run: source ~/.zshrc
e. Type a sentence at the prompt and press Control-G.
Expected: The command-line buffer is replaced with the refined version in place; cursor moves to end.

## 7. Hotkeys tab is gone

Open Settings (click the menu-bar icon → Settings).
Expected: Tabs visible are General, Triggers, Apps, Advanced, Live Mode.
The "Hotkeys" tab must not appear.

## 8. Migration — no stale KeyboardShortcuts entries

After running the new build for the first time (having previously run the old build), check:
  defaults read com.lingopulse.app
Expected: No keys starting with "KeyboardShortcuts_" appear in the output.
Also check the app-group suite:
  defaults read group.com.lingopulse.shared
Expected: Same — no "KeyboardShortcuts_" keys.

---

## Notes

- Steps 1–5 require Accessibility permission (System Settings → Privacy & Security → Accessibility → LingoPulse: ON).
- Step 6 requires the app to be built with build-bundle.sh so the shell scripts are bundled in Contents/Resources.
- Step 8 is only meaningful if you previously ran a build that had HotkeyManager active; on a fresh install there are no stale keys to migrate.
