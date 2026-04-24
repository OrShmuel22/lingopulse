import {
  List,
  ActionPanel,
  Action,
  LocalStorage,
  Clipboard,
  getSelectedText,
  getFrontmostApplication,
  showHUD,
  Toast,
  showToast,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./lib/api";
import type { Tone } from "./lib/types";

const TONES: { id: Tone; title: string; subtitle: string }[] = [
  {
    id: "Casual",
    title: "Casual",
    subtitle: "Concise, friendly, lowercase allowed",
  },
  { id: "Neutral", title: "Neutral", subtitle: "Balanced clarity and grammar" },
  {
    id: "Technical",
    title: "Technical",
    subtitle: "Precise, imperative, doc-style",
  },
  {
    id: "Professional",
    title: "Professional",
    subtitle: "Polite, structured, business",
  },
  {
    id: "Grammar-only",
    title: "Grammar-only",
    subtitle: "Fix grammar only; preserve tone",
  },
];

export default function Command() {
  const [lastTone, setLastTone] = useState<Tone | null>(null);
  const [appName, setAppName] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      const app = await getFrontmostApplication();
      setAppName(app.name);
      const last = await LocalStorage.getItem<string>(
        `tone_override.${app.name}`,
      );
      if (last && TONES.some((t) => t.id === last)) setLastTone(last as Tone);
    })();
  }, []);

  const runWithTone = async (tone: Tone) => {
    if (!appName) return;
    try {
      const sel = await getSelectedText();
      await LocalStorage.setItem(`tone_override.${appName}`, tone);
      const toast = await showToast({
        style: Toast.Style.Animated,
        title: `🧠 Refining as ${tone}...`,
      });
      const r = await api.refine(sel, appName, tone);
      await Clipboard.paste(r.refined);
      await toast.hide();
      await showHUD(`✨ ${tone}`);
    } catch (e) {
      await showHUD(`❌ ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  return (
    <List selectedItemId={lastTone ?? undefined}>
      {TONES.map((t) => (
        <List.Item
          key={t.id}
          id={t.id}
          title={t.title}
          subtitle={t.subtitle}
          actions={
            <ActionPanel>
              <Action
                title={`Refine as ${t.title}`}
                onAction={() => runWithTone(t.id)}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
