import {
  Clipboard,
  Toast,
  getSelectedText,
  getFrontmostApplication,
  showHUD,
  showToast,
} from "@raycast/api";
import { api } from "./lib/api";

export default async function Command() {
  let selection: string;
  try {
    selection = await getSelectedText();
  } catch {
    await showHUD("Nothing selected");
    return;
  }

  const app = await getFrontmostApplication();
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "🧠 Refining...",
  });

  try {
    const result = await api.refine(selection, app.name);
    await Clipboard.paste(result.refined);
    await toast.hide();
    await showHUD("✨ Refined — ⌘⌥Z to undo");
  } catch (e) {
    await toast.hide();
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("inference busy")) {
      await showHUD("⏳ Already refining...");
    } else if (msg.includes("timeout") || msg.includes("timed out")) {
      await showHUD("⏱ Timed out — try again");
    } else {
      await showHUD(`❌ ${msg}`);
    }
  }
}
