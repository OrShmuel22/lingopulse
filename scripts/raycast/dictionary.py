#!/Users/orshmuel/Projects/lingopluse/.venv/bin/python
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Find a Word
# @raycast.mode fullOutput
# @raycast.argument1 { "type": "text", "placeholder": "Describe the word..." }
#
# Optional parameters:
# @raycast.icon 📖
# @raycast.packageName LingoPulse
# @raycast.description Find precise English words from a description or Hebrew phrase

import sys

from lingopulse import apps, clipboard, config as cfg_mod, history, hud
from lingopulse.dictionary import build_prompt, detect_hebrew, parse_response, render_candidates
from lingopulse.ollama_client import OllamaClient, OllamaError, OllamaTimeoutError


def main():
    if len(sys.argv) < 2:
        print("Usage: dictionary.py <query>")
        sys.exit(1)

    query = sys.argv[1].strip()
    if not query:
        print("Empty query.")
        return

    config = cfg_mod.get()

    try:
        app = apps.frontmost()
    except Exception:
        app = "unknown"

    is_hebrew = detect_hebrew(query)
    prompt = build_prompt(query)

    client = OllamaClient()
    try:
        raw = client.generate(
            model=config["dictionary"]["model"],
            prompt=prompt,
            format="json",
            keep_alive=config["keepalive"]["ollama_keep_alive"],
            timeout=config["dictionary"]["timeout_seconds"],
        )
    except OllamaTimeoutError:
        hud.show_error("Dictionary timed out — try again")
        print("Error: request timed out.")
        return
    except OllamaError as e:
        hud.show_error(f"Dictionary error: {e}")
        print(f"Error: {e}")
        return

    candidates = parse_response(raw)
    if not candidates:
        hud.show_error("Dictionary couldn't parse the response — try rephrasing")
        print("Could not parse model response. Try rephrasing your query.")
        print()
        print("Raw response:")
        print(raw)
        return

    print(render_candidates(candidates))

    # Auto-copy first candidate word
    first_word = candidates[0].get("word", "")
    if first_word:
        clipboard.copy(first_word)
        print(f'\n"{first_word}" copied to clipboard.')

    history.append(
        {
            "mode": "dictionary",
            "query": query,
            "query_language": "hebrew" if is_hebrew else "english",
            "candidates": [
                {k: v for k, v in c.items() if k != "example"} for c in candidates
            ],
            "picked": first_word,
            "picked_index": 0,
            "app": app,
        }
    )


if __name__ == "__main__":
    main()
