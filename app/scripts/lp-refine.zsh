# LingoPulse zsh widget — refines the current command-line buffer in place.
#
# Install (one-time):
#   echo 'source ~/.config/lingopulse/lp-refine.zsh' >> ~/.zshrc
#   echo "bindkey '^G' lp-refine" >> ~/.zshrc
#
# Or run: lp-refine-install
# Then restart your shell (or: source ~/.zshrc).
#
# Requires: LingoPulse app running with shell bridge enabled, python3 (ships with macOS CLT).

# Guard against double-sourcing
if (( ${+functions[lp-refine]} )); then
    return 0
fi

lp-refine() {
    local cfg="${HOME}/.config/lingopulse"
    local token_file="${cfg}/shell-token"
    local port_file="${cfg}/shell-port"

    if [[ ! -r "$token_file" || ! -r "$port_file" ]]; then
        zle -M "lp-refine: LingoPulse not running or shell bridge disabled"
        return 1
    fi

    local token port resp refined
    token="$(<"$token_file")"
    port="$(<"$port_file")"

    resp="$(curl -sS --max-time 30 -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data-binary "$(printf '%s' "$BUFFER" | python3 -c 'import json,sys; print(json.dumps({"text": sys.stdin.read()}))')" \
        "http://127.0.0.1:${port}/refine")" || {
        zle -M "lp-refine: HTTP error"
        return 1
    }

    refined="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("refined",""), end="")')"

    if [[ -z "$refined" ]]; then
        zle -M "lp-refine: empty response"
        return 1
    fi

    BUFFER="$refined"
    CURSOR=${#BUFFER}
    zle reset-prompt
}

zle -N lp-refine

lp-refine-install() {
    local rc="${ZDOTDIR:-$HOME}/.zshrc"
    local source_line='source "${HOME}/.config/lingopulse/lp-refine.zsh"'
    local bind_line="bindkey '^G' lp-refine"

    if ! grep -qF 'lp-refine.zsh' "$rc" 2>/dev/null; then
        printf '\n%s\n' "$source_line" >> "$rc"
        echo "lp-refine-install: added source line to ${rc}"
    else
        echo "lp-refine-install: source line already present in ${rc}"
    fi

    if ! grep -qF "bindkey '^G' lp-refine" "$rc" 2>/dev/null; then
        printf '%s\n' "$bind_line" >> "$rc"
        echo "lp-refine-install: added bindkey to ${rc}"
    else
        echo "lp-refine-install: bindkey already present in ${rc}"
    fi

    echo "lp-refine-install: done. Run: source ${rc}"
}
