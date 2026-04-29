# LingoPulse

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-152%20passing-brightgreen)](#tests)

Local, private English refinement for macOS. A menu-bar app that polishes the text you've selected (or the field you're typing in) using a small language model running entirely on your machine. No cloud, no telemetry, no keystroke logging off-device.

Powered by [Ollama](https://ollama.com) on Apple Silicon.

---

## Highlights

- **Single keystroke refine** — Right ⌘ refines the current selection (or whole field).
- **Quick action menu** — Double-tap ⇧ for Refine · Preview · Tone · Undo · Find a Word · Capture Style. Number keys (1–9) pick instantly; Esc dismisses.
- **Live Mode (opt-in)** — Inline ghost-overlay suggestion after you pause typing. Apply with Enter, dismiss with Esc.
- **Terminal support** — `lp-refine` shell widget refines your zsh/bash buffer in place (Ctrl+G).
- **Tone presets** — Casual, Neutral, Professional, Technical, Grammar-only. All overrideable.
- **Hebrew + English dictionary** — Word lookup with definitions and example sentences.
- **Capture style** — Train the refiner on samples of your own writing.
- **Audit trail** — Every refinement is recorded locally with model, tone, duration, and char counts.

---

## Privacy & security

- **No network egress.** All inference runs against `127.0.0.1:11434` (Ollama). No analytics, no crash reports, no model telemetry.
- **No keystroke buffer.** Refines fire only on your trigger. Live Mode reads the focused field's value via Accessibility; nothing is logged off-device.
- **Shell bridge is loopback-only.** When enabled, the local HTTP server binds `127.0.0.1`, requires a generated bearer token (`~/.config/lingopulse/shell-token`, mode 0600), and rejects non-loopback connections.
- **Excluded apps by default.** 1Password and terminals never trigger Live Mode.

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M-series)
- [Ollama](https://ollama.com)

---

## Install

```bash
# 1. Install Ollama (one-time)
brew install ollama
brew services start ollama

# 2. Pull a model (one-time)
ollama pull gemma3:1b-it-qat        # ~800 MB, fastest
# or:  ollama pull gemma3:4b-it-qat  # ~2.5 GB, higher quality

# 3. Open LingoPulse.app
open /Applications/LingoPulse.app

# 4. Grant Accessibility permission when prompted
```

That's it. No Python, no daemons, no LaunchAgents.

---

## Triggers

| Trigger | Action |
|---------|--------|
| **Right ⌘** (single tap) | Refine. Selection if any; otherwise the whole focused field. |
| **Double-tap ⇧** | Quick action menu (1–6 to pick, Esc to dismiss). |
| **Ctrl+G** in zsh/bash | Refine the current command line in place (after installing the shell widget). |

Single key (Right ⌘ / Right ⌥ / Fn) and double-tap modifier (⌘ / ⌥ / ⇧) are configurable in **Settings → General → Triggers**.

---

## Terminal integration (zsh / bash)

iTerm/Terminal/Cursor's terminal pane don't expose Accessibility text. Use the shell widget instead:

1. Settings → Advanced → enable **Shell integration**.
2. Click **Install for zsh** (or bash). LingoPulse appends two lines to `~/.zshrc`:
   ```
   source "${HOME}/.config/lingopulse/lp-refine.zsh"
   bindkey '^G' lp-refine
   ```
3. Open a new terminal (or `source ~/.zshrc`).
4. Type a sentence at the prompt and press **Ctrl+G** — the line is replaced in place.

Bound to Ctrl+G by default. Re-bind by editing the `bindkey` line.

---

## Live Mode (optional)

Settings → Advanced → enable **Live Mode**. While typing in any AX-aware text field, LingoPulse refines after you pause typing for the configured debounce window (default 1.5 s) and offers an inline overlay.

- Apply with **Enter**, dismiss with **Esc**.
- Per-app excluded list under Settings → Apps.
- Disabled in 1Password and terminal apps by default.

---

## Configuration

`~/.config/lingopulse/config.json` is the source of truth. Defaults are sensible — only override what you want to change.

| Path | Purpose |
|------|---------|
| `fixer.model` | Default Ollama model used for refinement |
| `fixer.timeout_seconds` | Per-call timeout (default 15) |
| `keepalive.ollama_keep_alive` | How long Ollama keeps the model warm (default `30m`) |
| `keepalive.active_hours_start/end` | When to issue keep-alive pings |
| `ring_buffer.size` | Undo history depth (default 5) |
| `alerts.suppress_interval_seconds` | Modal-alert dedupe window (default 300) |

User data lives at:
- `~/.config/lingopulse/history.jsonl` — every refinement (audit log)
- `~/.config/lingopulse/style_examples.jsonl` — captured style examples
- `~/.cache/lingopulse/ring.json` — last N refines for undo

Per-user overrides set via Settings (model, prompts, tones) live in `NSUserDefaults` under the `lp.*` keys.

---

## Architecture

Single Swift menu-bar app. In-process: Ollama HTTP client, prompt builder, ring buffer, history store, AX selection bridge, Live Mode AX observer. No daemon. No Python. No Raycast.

```
app/Sources/LingoPulseApp/
├── Services/
│   ├── OllamaService          HTTP client (generate / generateStream / listModels) with retry+backoff
│   ├── Fixer                  Pre-correct → prompt build → Ollama call → record history
│   ├── AppConfig              Layered JSON config loader
│   ├── Prompts                Templates and tone descriptions
│   ├── Protection             Token/URL redaction round-trip
│   ├── HistoryStore           JSONL audit log
│   ├── RingBuffer             Bounded undo history
│   ├── AccessibilityService   AX read/write + clipboard fallback
│   ├── SelectionService       Synthesized ⌘C / ⌘V via CGEvent
│   ├── ClipboardService       Pasteboard snapshot/restore
│   ├── Dictionary             JSON-schema dictionary lookup
│   ├── StyleExamplesStore     Saved writing samples
│   ├── LiveTextMonitor        AXObserver-driven Live Mode
│   ├── KeepaliveOrchestrator  Periodic Ollama warm-up
│   ├── HealthMonitor          AX + daemon reachability poll
│   ├── ShellBridgeServer      Loopback HTTP /refine for shell widgets
│   ├── ShellInstaller         zsh/bash widget install
│   ├── Debouncer              Reusable Task-based debounce
│   ├── Alerts / Notifications User-visible feedback
│   ├── SpellCheck             NSSpellChecker pre-pass
│   └── ToneOverrides          User tone description overrides
├── Commands/                  Refine, Undo, Preview, Tone, Dictionary, CaptureStyle, Live
├── Views/                     QuickActionPanel, PreviewPanel, TonePickerPanel,
│                              DictionaryPanel, UndoFallbackPanel, GhostOverlayWindow,
│                              ModelsPromptsTab
├── AppDelegate                Bootstrap and pref observers
├── AppCoordinator             Command dispatch and refine state
├── TriggerMonitor             Single-key + double-tap state machine via CGEventTap
├── MenuBarController          NSStatusItem + menu and tooltip
├── SettingsWindow             4-tab settings UI (General, Models & Prompts, Apps, Advanced)
├── OnboardingWindow           First-run flow
└── Preferences                @Published-backed UserDefaults bridge
```

```
docs/
├── perf-tuning.md             Latency tuning notes
├── ui-research-2026.md        UX iteration findings
└── product/                   Decision records
benchmarks/                    Model benchmarking harness
scripts/                       Dev / release helpers
app/scripts/                   build-bundle.sh, build-dmg.sh, lp-refine.{zsh,bash}
```

---

## Build from source

```bash
cd app
swift build --configuration release
./scripts/build-bundle.sh release    # produces app/LingoPulse.app
./scripts/build-dmg.sh   release     # produces app/LingoPulse-<version>.dmg
```

Targets `swift-tools-version: 5.9`, `macOS 14+`. No external Swift dependencies; the project uses only AppKit, SwiftUI, ApplicationServices, and ServiceManagement.

---

## Tests

```bash
cd app
swift test
```

152 tests across 30+ suites covering: trigger state machine, AX read/write, Ollama client (with mocked URL session), prompt building, ring buffer persistence, dictionary JSON-schema parsing, shell-bridge auth, Live Mode debounce, health monitor, spell-check round-trip, and protection/redaction.

---

## Configuration matrix (models)

| Model | Size | Tok/s on M4 Air | Hebrew | Notes |
|-------|------|-----------------|--------|-------|
| `gemma3:1b-it-qat` | ~800 MB | ~85 | partial | Default. Best latency. |
| `gemma3:4b-it-qat` | ~2.5 GB | ~32 | good | Higher quality, slower. |
| `qwen2.5:3b` | ~1.9 GB | ~40 | weak | Stronger English grammar. |

Pick under **Settings → Models & Prompts → Refine model**. Different models for Refine vs. Dictionary cost a ~500 ms reload per alternation; the UI warns you.

---

## Honest limits

- Hebrew dictionary quality scales with the chosen model — Gemma 3 1B is fast but imperfect on rare words.
- Right ⌘ and Live Mode don't fire in apps that don't expose AX text (iTerm, Terminal, Cursor's terminal pane). Use the `lp-refine` shell widget there.
- Apple Intelligence Writing Tools is **not** used (no Hebrew support as of macOS 26.1).
- The shell bridge requires writing to your shell rc file. The installer is idempotent and prepends a comment marker, but review the diff if you keep your rc under version control.

---

## Migration from v1 (Python + Raycast)

```bash
launchctl bootout "gui/$(id -u)/com.lingopulse.warmup"    2>/dev/null
launchctl bootout "gui/$(id -u)/com.lingopulse.keepalive" 2>/dev/null
launchctl bootout "gui/$(id -u)/com.lingopulse.daemon"    2>/dev/null
rm -f ~/Library/LaunchAgents/com.lingopulse.*.plist
launchctl unsetenv OLLAMA_KEEP_ALIVE 2>/dev/null
```

Your `~/.config/lingopulse/` data carries over verbatim.

---

## Uninstall

```bash
rm -rf /Applications/LingoPulse.app
rm -rf ~/.config/lingopulse ~/.cache/lingopulse
```

---

## License

MIT. See [LICENSE](LICENSE).

---

## Contributing

Issues and PRs welcome. Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`) and `swift test` passing are required for merge.
