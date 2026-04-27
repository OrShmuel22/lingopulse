# LingoPulse bash widget — refines the current readline buffer in place.
#
# Install (one-time):
#   echo 'source ~/.config/lingopulse/lp-refine.bash' >> ~/.bashrc
#   echo "bind -x '\"\\C-g\": lp-refine'" >> ~/.bashrc
#
# Then restart your shell (or: source ~/.bashrc).
#
# Requires: LingoPulse app running with shell bridge enabled, python3 (ships with macOS CLT).

# Guard against double-sourcing
if declare -f lp-refine > /dev/null 2>&1; then
    return 0
fi

lp-refine() {
    local cfg="${HOME}/.config/lingopulse"
    local token_file="${cfg}/shell-token"
    local port_file="${cfg}/shell-port"

    if [[ ! -r "$token_file" || ! -r "$port_file" ]]; then
        echo "lp-refine: LingoPulse not running or shell bridge disabled" >&2
        return 1
    fi

    local token port resp refined
    token="$(<"$token_file")"
    port="$(<"$port_file")"

    resp="$(curl -sS --max-time 30 -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data-binary "$(printf '%s' "$READLINE_LINE" | python3 -c 'import json,sys; print(json.dumps({"text": sys.stdin.read()}))')" \
        "http://127.0.0.1:${port}/refine")" || return 1

    refined="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("refined",""), end="")')"

    [[ -z "$refined" ]] && return 1

    READLINE_LINE="$refined"
    READLINE_POINT=${#READLINE_LINE}
}

lp-refine-install() {
    local rc="${BASH_ENV:-${HOME}/.bashrc}"
    local source_line='source "${HOME}/.config/lingopulse/lp-refine.bash"'
    local bind_line='bind -x '"'"'"\C-g": lp-refine'"'"

    if ! grep -qF 'lp-refine.bash' "$rc" 2>/dev/null; then
        printf '\n%s\n' "$source_line" >> "$rc"
        echo "lp-refine-install: added source line to ${rc}"
    else
        echo "lp-refine-install: source line already present in ${rc}"
    fi

    if ! grep -qF '"\\C-g": lp-refine' "$rc" 2>/dev/null; then
        printf '%s\n' "$bind_line" >> "$rc"
        echo "lp-refine-install: added bind line to ${rc}"
    else
        echo "lp-refine-install: bind line already present in ${rc}"
    fi

    echo "lp-refine-install: done. Run: source ${rc}"
}
