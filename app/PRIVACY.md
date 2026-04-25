# LingoPulse Privacy

## Keystroke flow

Keystrokes are intercepted by the LingoPulseIME Input Method Extension via
macOS's InputMethodKit framework.  Each printable character is appended to an
in-memory buffer held exclusively inside the IME process.  The buffer is cleared
on every session boundary: Enter, Escape, arrow key, Backspace, or focus change.
Characters are never written to disk by the IME bundle.

## Daemon — localhost only

When the buffer reaches the debounce threshold the IME sends a single HTTPS
POST to `http://127.0.0.1:17823/refine` — the LingoPulse daemon running on the
same machine.  No data is transmitted to the internet.  The daemon address is
user-configurable in Preferences and defaults to localhost only.

## No telemetry

LingoPulse collects no usage metrics, crash reports, or analytics.  There are
no third-party SDKs, no background beacons, and no network requests to any
external server.  The only outbound traffic is the localhost refine call
described above.

## Buffer reset triggers

The in-memory typing buffer is reset to empty on any of the following events,
preventing stale text from being sent to the daemon:

- Enter / Return
- Escape
- Any arrow key or cursor-movement command
- Backspace or forward-delete (including word and line variants)
- Server deactivation (focus leaves the input field)
- Secure input mode detected (`IsSecureEventInputEnabled()` returns true)
- The frontmost application is on the user-configured exclusion list

## Build-from-source verifiability

The entire Mac client — main app, IME bundle, and daemon — is open source Swift
and Python respectively.  All dependencies are declared in `Package.swift` and
`pyproject.toml`.  Reproducible builds can be produced with:

```
cd app && swift build && swift test
cd app && ./scripts/build-ime-bundle.sh debug
cd app && ./scripts/build-bundle.sh debug
```

No binary blobs, pre-compiled frameworks, or closed-source dependencies are
included in the repository.
