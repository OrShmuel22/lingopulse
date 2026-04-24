#!/usr/bin/env bash
set -euo pipefail

# Read model from config.json; fall back to gemma4:e4b
CONFIG="$HOME/.config/lingopulse/config.json"
MODEL="gemma4:e4b"
KEEP_ALIVE="30m"

if [ -f "$CONFIG" ]; then
    # Parse with jq if available, else use python
    if command -v jq >/dev/null 2>&1; then
        M=$(jq -r '.fixer.model // empty' "$CONFIG" 2>/dev/null || echo "")
        K=$(jq -r '.keepalive.ollama_keep_alive // empty' "$CONFIG" 2>/dev/null || echo "")
    else
        M=$(/usr/bin/python3 -c "import json,sys; print(json.load(open('$CONFIG')).get('fixer',{}).get('model',''))" 2>/dev/null || echo "")
        K=$(/usr/bin/python3 -c "import json,sys; print(json.load(open('$CONFIG')).get('keepalive',{}).get('ollama_keep_alive',''))" 2>/dev/null || echo "")
    fi
    [ -n "$M" ] && MODEL="$M"
    [ -n "$K" ] && KEEP_ALIVE="$K"
fi

ping_ollama() {
    curl -s -m 60 -X POST http://127.0.0.1:11434/api/generate \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"$MODEL\",\"prompt\":\" \",\"keep_alive\":\"$KEEP_ALIVE\",\"stream\":false}" \
        -o /dev/null 2>&1
}

# Try once, retry once after 10s if it fails (Ollama might be starting)
if ! ping_ollama; then
    sleep 10
    ping_ollama || true
fi

exit 0
