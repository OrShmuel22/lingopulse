---
title: Fixer — Cold-Start & Keep-Alive
status: DECIDED
created: 2026-04-24
updated: 2026-04-24
related_problems: [B1, F8, M2]
---

# Fixer — Cold-Start & Keep-Alive

> **Status:** DECIDED — ready for `/dev`
> **Created:** 2026-04-24 | **Updated:** 2026-04-24

## The Real Problem

Your first press of the day — or after a lunch break — takes 10+ seconds of total silence. By day three, you've trained yourself to type the message carefully instead of reaching for the hotkey. The <800 ms performance target in the spec is fiction outside a 5-minute window after warmup.

Two failure modes compound:
1. **Actual latency:** Ollama's default `OLLAMA_KEEP_ALIVE=5m` unloads the model after 5 min idle. Every return from idle pays a 3–8 s disk-load cost.
2. **Perceived latency:** Even when inference is warm, no feedback appears until the result lands. A 600 ms silence feels like "nothing happened."

## Scenarios

| Moment | What you need | What the spec delivers |
|--------|--------------|-----------------------|
| 09:15, Slack, first refine of the day | Refined text in <1 s | 8–15 s silence. You retry; now two jobs queued. |
| Post-lunch, 90 min idle | Near-instant | Cold reload. Same 8–15 s. |
| 10-min gap during coding | Warm | KEEP_ALIVE exceeded. Cold. |
| Heavy RAM pressure (Chrome + Docker + Cursor indexing) | LingoPulse stays warm | Model paged out silently; next press is cold. |
| Any press | Confirmation the hotkey fired | No HUD appears until inference completes; 2 s of silence looks like a broken press. |

## Decision

**Option D with configurable schedule: login warmup + `OLLAMA_KEEP_ALIVE=30m` + LaunchAgent pings during active hours + explicit immediate HUD feedback on every press.**

All timing knobs live in `~/.config/lingopulse/config.json` so you can tune without editing code.

### Why D wins (alternatives considered)

- **A (`KEEP_ALIVE=-1`)**: pins ~2.5 GB on a 24 GB M4 Air 24/7 even while sleeping. ~10% of RAM permanently, for no benefit at 3 am.
- **B (always-on 4-min ping)**: same RAM tax as A, slightly more complex.
- **C (predictive warmup on typing signals)**: requires global Accessibility observation of keystrokes. Privacy surface, fragile, complexity not worth it for v1.
- **D**: warm during your actual working hours, free at night, cold load absorbed at login (not at the hotkey), explicit feedback handles the remaining edge cases.

## Details

### Login warmup

- A `LaunchAgent` (`com.lingopulse.warmup.plist`, `RunAtLoad=true`) fires once at login.
- Runs a ping script: `curl -s http://127.0.0.1:11434/api/generate -d '{"model":"gemma3:4b-it-qat","prompt":" ","keep_alive":"30m","stream":false}'`.
- The one cold load of the day happens while you're unlocking your screen, before you reach for a hotkey.
- If Ollama isn't running yet (user hasn't launched it), the script retries once after 10 s, then exits silently. Next scheduled ping will pick it up.

### Keep-alive & scheduled pings

- Ollama env: `OLLAMA_KEEP_ALIVE=30m` (set via `launchctl setenv` in the install script, or in Ollama's own launch config).
- A second `LaunchAgent` (`com.lingopulse.keepalive.plist`) runs the same ping every 25 minutes between 08:00 and 22:00 (configurable).
- 25-min interval chosen to stay comfortably inside the 30-min keep-alive window even with clock drift.
- Between 22:00 and 08:00, no pings. Model unloads after last ping + 30 min (≈ 22:25). Nighttime RAM is free.

### Immediate HUD feedback (solves the perception half)

This runs **regardless of whether the model is warm**. It exists so a 600 ms cold-check doesn't feel like a broken press.

| Elapsed from hotkey press | HUD state |
|---|---|
| 0 ms | *(nothing — avoid flicker for fast cases)* |
| 100 ms | "🧠 Refining…" HUD appears |
| 2 s | HUD adds subtext: "Loading model — first use of the session…" |
| 15 s | HUD shows error with Retry / Cancel buttons |
| success at any point | HUD transitions to the diff toast from `fixer-undo.md` |

This piggybacks on the diff-toast infrastructure from `fixer-undo.md`; it's the same HUD component, earlier.

### Configurability

All knobs live in `~/.config/lingopulse/config.json`:

```json
{
  "keepalive": {
    "enabled": true,
    "ollama_keep_alive": "30m",
    "ping_interval_minutes": 25,
    "active_hours_start": "08:00",
    "active_hours_end": "22:00",
    "login_warmup": true
  },
  "feedback": {
    "hud_show_after_ms": 100,
    "hud_cold_start_notice_after_ms": 2000,
    "hud_error_after_ms": 15000
  }
}
```

Defaults picked so you never need to edit this file, but the knobs exist for tuning if M4 Air thermals surprise us or Ollama version behavior changes.

### Concurrency

Already covered by `fixer-undo.md` Task 7 (inference lock). No new work here.

## Open Questions (flag for /dev)

1. **LaunchAgent install UX:** a personal tool so no installer needed, but the plist still needs to land in `~/Library/LaunchAgents/` and be loaded with `launchctl bootstrap`. A 10-line `install.sh` is enough — decide during /dev whether to script it or just document the commands.
2. **Ping script resilience:** if Ollama isn't running at the scheduled time, the ping silently fails. Acceptable for v1. If this causes flaky warm states, add a `brew services start ollama` in the login warmup.
3. **Thermal reality on M4 Air (fanless):** gemma3:4b-it-qat inference on short (<50 word) prompts should not sustain long enough to throttle. If longer refinements (emails) show degraded wall-clock time during sustained use, revisit quantization or model size. Not a v1 blocker.

## Tasks (for /dev)

| # | Task | Area | Definition of Done |
|---|------|------|---------------------|
| 1 | Ship config.json schema + loader with documented defaults | Backend / Python | `~/.config/lingopulse/config.json` is created on first run with the defaults shown in this doc. Changing a value and restarting Raycast picks up the change. Missing keys fall back to defaults without crashing. |
| 2 | Ship login warmup LaunchAgent | Infrastructure | After `launchctl bootstrap`-ing the plist, logging out and back in results in Ollama showing `gemma3:4b-it-qat` loaded in `ollama ps` within 30 s of login, with no hotkey press. |
| 3 | Ship scheduled keep-alive LaunchAgent | Infrastructure | At 09:00 (inside active hours), `ollama ps` shows `gemma3:4b-it-qat` loaded. At 23:00 + 35 min (outside active hours + past keep-alive), `ollama ps` shows it unloaded. Interval and active hours honor `config.json`. |
| 4 | Set OLLAMA_KEEP_ALIVE=30m in Ollama env | Infrastructure | `launchctl getenv OLLAMA_KEEP_ALIVE` returns `30m`. After a fresh request, `ollama ps` shows the model remains loaded for ≥28 min of idle. Value is read from config.json, not hardcoded. |
| 5 | Immediate HUD feedback on hotkey press (≤100ms) | UX | Pressing `Cmd+Opt+E` causes a "🧠 Refining…" HUD to appear within 100 ms, even when inference takes longer. If the refinement completes in <100 ms (impossibly fast), no flicker HUD appears. |
| 6 | Cold-start HUD upgrade after 2s | UX | If inference is still running 2 s after the hotkey press, the HUD updates with "Loading model — first use of the session…" subtext. Threshold reads from config.json. |
| 7 | Error HUD with Retry after 15s | UX | If inference is still running 15 s after the hotkey press, the HUD shows an error state with "Retry" and "Cancel" actions. Retry re-submits the same selection; Cancel restores the original selection and exits. |
| 8 | Install script for LaunchAgents | Infrastructure / Docs | Running `./install.sh` (or equivalent) copies both plists to `~/Library/LaunchAgents/`, runs `launchctl bootstrap`, and sets `OLLAMA_KEEP_ALIVE`. Running it twice is idempotent. |
| 9 | Measure and record actual latency on M4 Air | QA | `docs/product/fixer-benchmarks.md` exists with measured end-to-end latency for: cold (after reboot), warm-recent-use, warm-after-30min-idle, under memory pressure (Chrome + Docker running). If warm > 1.5 s end-to-end, flag for investigation before shipping. |

## Hand-off

Tasks 1–9 go to `/dev`. Decisions locked. Remaining ambiguity is packaging (install script vs. manual `launchctl`) and measurement-driven (benchmarks may surface a thermal/throttle issue specific to M4 Air that we'll handle reactively).
