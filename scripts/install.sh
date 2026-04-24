#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
CONFIG_DIR="$HOME/.config/lingopulse"
CACHE_DIR="$HOME/.cache/lingopulse"
LOGS_DIR="$HOME/Library/Logs"

echo "LingoPulse install — project: $PROJECT_ROOT"

# --- Preflight ---
echo ""
echo "== Preflight =="

# Python 3.11+
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found. Install Python 3.11 or 3.12." >&2
    exit 1
fi
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
echo "Python: $PY_VER"

# Ollama
if ! command -v ollama >/dev/null 2>&1; then
    echo "ERROR: ollama not found. Install with 'brew install ollama'." >&2
    exit 1
fi
echo "Ollama: $(ollama --version 2>&1 | head -1)"

# Ollama daemon reachable
if ! curl -s -m 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "Ollama daemon not reachable — starting service..."
    brew services start ollama
    sleep 3
fi

# venv
if [ ! -x "$PROJECT_ROOT/.venv/bin/python" ]; then
    echo "ERROR: .venv not found at $PROJECT_ROOT/.venv. Run 'python3 -m venv .venv && .venv/bin/pip install -e .'" >&2
    exit 1
fi
echo "venv: $($PROJECT_ROOT/.venv/bin/python --version)"

# --- Directories ---
mkdir -p "$CONFIG_DIR" "$CACHE_DIR" "$LAUNCH_AGENTS_DIR" "$LOGS_DIR"

# --- Initialize config ---
# First run of any lingopulse Python will create the default config.json.
# Ensure it exists by triggering a config load.
"$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; config.get()" >/dev/null
echo "Config: $CONFIG_DIR/config.json"

# --- Read model from config ---
MODEL=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['fixer']['model'])")
KEEP_ALIVE=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['keepalive']['ollama_keep_alive'])")
START_HOUR=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['keepalive']['active_hours_start'].split(':')[0])")
END_HOUR=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['keepalive']['active_hours_end'].split(':')[0])")
INTERVAL=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['keepalive']['ping_interval_minutes'])")

echo "Model: $MODEL"
echo "Active hours: $START_HOUR:00 – $END_HOUR:00 every ${INTERVAL}m"

# --- Model pull ---
if ! ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$MODEL"; then
    echo "Pulling model $MODEL..."
    ollama pull "$MODEL"
else
    echo "Model $MODEL already pulled."
fi

# --- GEC model preload ---
if "$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; print(config.get().get('pipeline',{}).get('gec_enabled', True))" | grep -qi "true"; then
    GEC_MODEL=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; print(config.get().get('pipeline',{}).get('gec_model','pszemraj/grammar-synthesis-small'))")
    echo "Pre-downloading GEC model: $GEC_MODEL (first run ~30-60s)..."
    "$PROJECT_ROOT/.venv/bin/python" -c "
from lingopulse import gec
gec.warmup()
print('GEC model ready.')
" || {
        echo "WARN: GEC model preload failed. Fixer will fall back to LLM-only until GEC is available."
    }
else
    echo "GEC disabled in config — skipping preload."
fi

# --- Set Ollama keep-alive env ---
launchctl setenv OLLAMA_KEEP_ALIVE "$KEEP_ALIVE"
echo "OLLAMA_KEEP_ALIVE=$KEEP_ALIVE set via launchctl."

# --- Generate StartCalendarInterval array ---
gen_interval() {
    local start_h="$1" end_h="$2" step="$3"
    local h m
    # Force decimal interpretation to avoid octal errors on e.g. 08, 09
    start_h=$((10#$start_h))
    end_h=$((10#$end_h))
    step=$((10#$step))
    echo "    <array>"
    for ((h=start_h; h<=end_h; h++)); do
        for ((m=0; m<60; m+=step)); do
            # Skip the boundary top-of-hour past end_h
            if [ "$h" -eq "$end_h" ] && [ "$m" -gt 0 ]; then
                break
            fi
            echo "        <dict>"
            echo "            <key>Hour</key>"
            echo "            <integer>$h</integer>"
            echo "            <key>Minute</key>"
            echo "            <integer>$m</integer>"
            echo "        </dict>"
        done
    done
    echo "    </array>"
}

CALENDAR_INTERVAL=$(gen_interval "$START_HOUR" "$END_HOUR" "$INTERVAL")

# --- Render plists ---
WARMUP_PLIST="$LAUNCH_AGENTS_DIR/com.lingopulse.warmup.plist"
KEEPALIVE_PLIST="$LAUNCH_AGENTS_DIR/com.lingopulse.keepalive.plist"
DAEMON_PLIST="$LAUNCH_AGENTS_DIR/com.lingopulse.daemon.plist"

sed -e "s|{{PROJECT_ROOT}}|$PROJECT_ROOT|g" \
    -e "s|{{HOME}}|$HOME|g" \
    "$PROJECT_ROOT/launch_agents/com.lingopulse.warmup.plist.template" > "$WARMUP_PLIST"

# keepalive: substitute CALENDAR_INTERVAL via python (sed is brittle with multiline)
"$PROJECT_ROOT/.venv/bin/python" - <<PYEOF
import pathlib
t = pathlib.Path("$PROJECT_ROOT/launch_agents/com.lingopulse.keepalive.plist.template").read_text()
t = t.replace("{{PROJECT_ROOT}}", "$PROJECT_ROOT")
t = t.replace("{{HOME}}", "$HOME")
t = t.replace("{{CALENDAR_INTERVAL_ARRAY}}", """$CALENDAR_INTERVAL""")
pathlib.Path("$KEEPALIVE_PLIST").write_text(t)
PYEOF

sed -e "s|{{PROJECT_ROOT}}|$PROJECT_ROOT|g" \
    -e "s|{{HOME}}|$HOME|g" \
    "$PROJECT_ROOT/launch_agents/com.lingopulse.daemon.plist.template" > "$DAEMON_PLIST"

echo "Plists written:"
echo "  $WARMUP_PLIST"
echo "  $KEEPALIVE_PLIST"
echo "  $DAEMON_PLIST"

# --- Load LaunchAgents (idempotent) ---
GUI_UID="gui/$(id -u)"

# Bootout first (ignore errors — may not be loaded)
launchctl bootout "$GUI_UID/com.lingopulse.warmup" 2>/dev/null || true
launchctl bootout "$GUI_UID/com.lingopulse.keepalive" 2>/dev/null || true
launchctl bootout "$GUI_UID/com.lingopulse.daemon" 2>/dev/null || true

# Now bootstrap
launchctl bootstrap "$GUI_UID" "$WARMUP_PLIST"
launchctl bootstrap "$GUI_UID" "$KEEPALIVE_PLIST"
launchctl bootstrap "$GUI_UID" "$DAEMON_PLIST"
echo "LaunchAgents loaded."

# --- Wait for daemon to be reachable ---
PORT=$("$PROJECT_ROOT/.venv/bin/python" -c "from lingopulse import config; c=config.get(); print(c['daemon']['port'])")
echo "Waiting for daemon on port $PORT..."
for i in $(seq 1 10); do
    if curl -sf "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
        echo "Daemon is up."
        break
    fi
    if [ "$i" -eq 10 ]; then
        echo "ERROR: Daemon did not start within 10 seconds. Check logs at $HOME/Library/Logs/lingopulse-daemon.log" >&2
        exit 1
    fi
    sleep 1
done

# --- Immediate warmup (so user doesn't wait for next scheduled tick) ---
bash "$PROJECT_ROOT/scripts/warmup_ping.sh" &
echo "Warming model in background..."

# --- Summary ---
echo ""
echo "== Install complete =="
echo ""
echo "Next steps:"
echo "  1. Register the Raycast extension (one-time):"
echo "     cd $PROJECT_ROOT/extension && npm ci && npm run dev"
echo "     Leave this running — Raycast picks up the extension in dev mode."
echo ""
echo "  2. In Raycast → Extensions → find LingoPulse → assign hotkeys (suggested):"
echo "     ⌘⌥E        Refine Selection"
echo "     ⌘⌥⇧E       Refine Selection (Preview)"
echo "     ⌘⌥Z        Undo Last Refinement"
echo "     ⌘⌥T        Refine with Tone"
echo "     ⌘⌥S        Find a Word"
echo "     ⌘⌥M        Save as Style Example"
echo ""
echo "  3. Config lives at $CONFIG_DIR/config.json"
echo "     Logs: $LOGS_DIR/lingopulse-{warmup,keepalive}.log"
echo ""
echo "  LingoPulse daemon running at http://127.0.0.1:$PORT"
echo "  Logs: ~/Library/Logs/lingopulse-daemon.log"
echo ""
