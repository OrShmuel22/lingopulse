#!/usr/bin/env bash
set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
GUI_UID="gui/$(id -u)"

echo "LingoPulse uninstall..."

launchctl bootout "$GUI_UID/com.lingopulse.warmup" 2>/dev/null || true
launchctl bootout "$GUI_UID/com.lingopulse.keepalive" 2>/dev/null || true
launchctl bootout "$GUI_UID/com.lingopulse.daemon" 2>/dev/null || true

rm -f "$LAUNCH_AGENTS_DIR/com.lingopulse.warmup.plist"
rm -f "$LAUNCH_AGENTS_DIR/com.lingopulse.keepalive.plist"
rm -f "$LAUNCH_AGENTS_DIR/com.lingopulse.daemon.plist"

launchctl unsetenv OLLAMA_KEEP_ALIVE

echo "LaunchAgents removed."
echo ""
echo "User data preserved at:"
echo "  ~/.config/lingopulse/   (config + history + tone overrides)"
echo "  ~/.cache/lingopulse/    (ring buffer + pending preview)"
echo "  ~/Library/Logs/lingopulse-*.log"
echo ""
echo "Remove manually if you want a clean slate."
