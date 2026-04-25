# LingoPulse IME — Dogfood Checklist

A 10-minute walkthrough to manually verify IME compatibility across apps. After each session, update `IME-COMPAT.md` with results.

---

## Step 1: Build and install bundle

```bash
cd /Users/orshmuel/Projects/lingopluse/app
swift build && swift test
./scripts/build-bundle.sh debug
```

Expected output ends with:
```
==> Bundle: .../app/LingoPulse.app
Run with: open '.../app/LingoPulse.app'
```

Then install the bundle:
```bash
open /Users/orshmuel/Projects/lingopluse/app/LingoPulse.app
```

---

## Step 2: Enable in System Settings

Open Accessibility settings directly:
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Or open Input Method settings:
```bash
open "x-apple.systempreferences:com.apple.preference.keyboard"
```

Checklist:
- [ ] LingoPulse appears in Accessibility list
- [ ] Toggle is ON for LingoPulse
- [ ] If previously granted, no re-prompt is needed (ad-hoc signing persists the grant)

To verify the IME is registered:
```bash
ls ~/Library/Input\ Methods/LingoPulseIME.app
```

To tail diagnostic logs while testing:
```bash
log stream --predicate 'eventMessage CONTAINS "LingoPulseIME"' --level debug
```

---

## Step 3: Test each app surface (~10 min)

For each app below, type the sample text, pause 2 seconds, and observe whether the suggestion chip appears. Then press Tab to accept or Esc to dismiss.

### 3a. TextEdit (baseline — should always work)

1. Open TextEdit (`open -a TextEdit`)
2. Create new plain text document
3. Type: `teh quick brown fox jumpped over teh lazy dog`
4. Wait 2 seconds
5. Expected: suggestion chip appears above cursor
6. Press Tab — expected: text replaced with corrected version
7. Press Cmd-Z — expected: undo restores original text

- [ ] Chip appeared
- [ ] Tab accepted
- [ ] Esc dismissed (repeat with fresh text)
- [ ] Undo worked

### 3b. Slack (Electron)

1. Open Slack, focus any message compose box
2. Type: `hey can u review this pr? i think its missing a few edge cases`
3. Wait 2 seconds
4. Expected: suggestion chip appears
5. Press Tab to accept

- [ ] Chip appeared
- [ ] Tab accepted (or note if clipboard fallback triggered)
- [ ] Replacement text is accurate (no extra chars, cursor in right place)

### 3c. Notion (Electron)

1. Open Notion, focus a text block
2. Type: `Im writing this to folowup on are previous meeting. Their should be notes avaliable.`
3. Wait 2 seconds
4. Expected: chip appears

- [ ] Chip appeared
- [ ] Tab accepted or Partial (note behavior)

### 3d. VS Code (Electron)

1. Open VS Code, open any plain text file or untitled file
2. Type: `this is a test sentance with some typos that lingopulse should fix`
3. Wait 2 seconds
4. Note: Tab in VS Code may trigger editor autocomplete instead of IME accept

- [ ] Chip appeared
- [ ] Tab accepted / Partial (Tab hijacked by editor) / Fail

### 3e. Safari — textarea

1. Open Safari, navigate to https://www.browserling.com/tools/text-editor or any page with a `<textarea>`
2. Type: `Im writting this email to folowup. Their going to there office tomorow.`
3. Wait 2 seconds

- [ ] Chip appeared
- [ ] Tab accepted or Partial

### 3f. Mail (compose)

1. Open Mail, compose a new message
2. Click in the body field
3. Type: `I wanted to reach out reagrding are upcomming meeting. Please let me no if you can attend.`
4. Wait 2 seconds

- [ ] Chip appeared
- [ ] Tab accepted

### 3g. Terminal (should be excluded)

1. Open Terminal.app
2. Type anything
3. Expected: NO chip appears (Terminal is in the default exclusion list)

- [ ] No chip appeared (correct behavior)

Check the diagnostic log to confirm:
```bash
log stream --predicate 'eventMessage CONTAINS "LingoPulseIME"' --level debug
# Look for: "excluded" or "activationPolicy" lines for Terminal
```

---

## Step 4: Update IME-COMPAT.md with results

After testing, open `app/docs/IME-COMPAT.md` and update each row:
- **Pass** — everything works as expected
- **Partial** — chip appears but accept/replacement has issues (describe in Notes)
- **Fail** — no chip, or chip breaks the app's text field
- Leave **Untested** for surfaces you did not test this session

Add the date at the top of the file.

---

## Interpreting diagnostic logs

The IME logs app activation events automatically. After installing and launching LingoPulse, switch between apps and watch:

```
LingoPulseIME [AppDiag]: active app: Slack | policy: regular | IME input likely: YES
LingoPulseIME [AppDiag]: active app: Finder | policy: regular | IME input likely: NO (no text focus expected)
LingoPulseIME [AppDiag]: active app: iTerm2 | policy: regular | IME input likely: NO (excluded)
```

- `IME input likely: YES` — app has a regular activation policy and is not excluded; IME should engage when you type in a text field
- `IME input likely: NO (excluded)` — app is in the exclusion list; IME is disabled for it
- `IME input likely: NO (no text focus expected)` — app does not present editable text fields (e.g. Finder, Preview)

If you see `YES` for an app but no chip appears, that indicates an IME incompatibility worth noting as **Fail** or **Partial** in the matrix.
