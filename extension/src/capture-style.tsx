import {
  getSelectedText,
  getFrontmostApplication,
  showHUD,
} from "@raycast/api";
import { api } from "./lib/api";

export default async function Command() {
  try {
    const text = await getSelectedText();
    if (!text.trim()) {
      await showHUD("Nothing selected");
      return;
    }
    const app = await getFrontmostApplication();
    await api.captureStyle(text, app.name);
    await showHUD("📝 Saved as style example");
  } catch (e) {
    await showHUD(`❌ ${e instanceof Error ? e.message : String(e)}`);
  }
}
