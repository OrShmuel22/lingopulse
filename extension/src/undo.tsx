import { Clipboard, showHUD } from "@raycast/api";
import { api } from "./lib/api";

export default async function Command() {
  try {
    const result = await api.undo();
    try {
      await Clipboard.paste(result.original);
      await showHUD("↩︎ Reverted");
    } catch {
      await Clipboard.copy(result.original);
      await showHUD("📋 Original copied — ⌘V to paste");
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("nothing to undo")) {
      await showHUD("Nothing to undo");
    } else {
      await showHUD(`❌ ${msg}`);
    }
  }
}
