#!/usr/bin/env bash
# Configure Ollama environment for LingoPulse perf wins.
#
# Sets three knobs documented at https://docs.ollama.com/faq:
#   OLLAMA_FLASH_ATTENTION=1    — enable flash attention (less memory, faster on long ctx)
#   OLLAMA_KV_CACHE_TYPE=q8_0   — quantize KV cache to q8_0 (~50% less RAM, tiny precision loss)
#   OLLAMA_NUM_PARALLEL=2       — allow Refine + Dictionary to run concurrently
#
# Usage:
#   ./scripts/setup_ollama_env.sh           # print what to do
#   ./scripts/setup_ollama_env.sh --apply   # run launchctl setenv (still need to restart Ollama)
#
# Ollama must be restarted after applying. This script does not restart it.

set -euo pipefail

VARS=(
  "OLLAMA_FLASH_ATTENTION=1"
  "OLLAMA_KV_CACHE_TYPE=q8_0"
  "OLLAMA_NUM_PARALLEL=2"
)

print_block() {
  echo "================================================================="
  echo "$1"
  echo "================================================================="
}

current_env() {
  print_block "Current environment (in this shell)"
  for v in "${VARS[@]}"; do
    name="${v%%=*}"
    val="${!name:-<unset>}"
    echo "  $name=$val"
  done
  echo
}

apply_launchctl() {
  print_block "Applying via launchctl setenv (affects newly started processes)"
  for v in "${VARS[@]}"; do
    name="${v%%=*}"
    val="${v#*=}"
    echo "  launchctl setenv $name $val"
    launchctl setenv "$name" "$val"
  done
  echo
  echo "Done. launchctl setenv only persists until reboot. For permanence,"
  echo "see the 'Persist across reboot' section below."
  echo
}

print_restart_instructions() {
  print_block "RESTART OLLAMA to pick up new env vars"
  cat <<'EOF'
If you run Ollama via the menu-bar app:
  1. Click the Ollama icon in the menu bar → Quit Ollama
  2. Re-open Ollama from Applications

If you run `ollama serve` from a terminal:
  1. Stop the running serve (Ctrl-C)
  2. Run again from a fresh shell so it inherits the new env

Verify with:
  curl -s http://127.0.0.1:11434/api/version
  ollama ps                    # shows loaded models with KV size

EOF
}

print_persistence_instructions() {
  print_block "Persist across reboot"
  cat <<'EOF'
launchctl setenv is reset on reboot. Two options for permanence:

OPTION A (recommended for ollama serve users):
  Add to ~/.zshrc (or ~/.bash_profile):
    export OLLAMA_FLASH_ATTENTION=1
    export OLLAMA_KV_CACHE_TYPE=q8_0
    export OLLAMA_NUM_PARALLEL=2

OPTION B (recommended for menu-bar app users):
  Create ~/Library/LaunchAgents/com.user.ollama-env.plist with the
  contents below, then run:
    launchctl load ~/Library/LaunchAgents/com.user.ollama-env.plist

  ----- com.user.ollama-env.plist -----
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
   "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.user.ollama-env</string>
    <key>ProgramArguments</key>
    <array>
      <string>sh</string>
      <string>-c</string>
      <string>launchctl setenv OLLAMA_FLASH_ATTENTION 1; launchctl setenv OLLAMA_KV_CACHE_TYPE q8_0; launchctl setenv OLLAMA_NUM_PARALLEL 2</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
  </dict>
  </plist>

EOF
}

main() {
  current_env
  if [[ "${1:-}" == "--apply" ]]; then
    apply_launchctl
  else
    print_block "Dry run — no changes made. Re-run with --apply to set values."
    for v in "${VARS[@]}"; do
      name="${v%%=*}"
      val="${v#*=}"
      echo "  Would run: launchctl setenv $name $val"
    done
    echo
  fi
  print_restart_instructions
  print_persistence_instructions
}

main "$@"
