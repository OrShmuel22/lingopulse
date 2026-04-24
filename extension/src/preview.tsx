import {
  Detail,
  ActionPanel,
  Action,
  Clipboard,
  showHUD,
  useNavigation,
  getSelectedText,
  getFrontmostApplication,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./lib/api";
import type { RefineResponse } from "./lib/types";

export default function Command() {
  const [result, setResult] = useState<RefineResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { pop } = useNavigation();

  useEffect(() => {
    (async () => {
      try {
        const sel = await getSelectedText();
        const app = await getFrontmostApplication();
        const r = await api.refine(sel, app.name);
        setResult(r);
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
      }
    })();
  }, []);

  if (error) return <Detail markdown={`# Error\n\n\`\`\`\n${error}\n\`\`\``} />;
  if (!result) return <Detail isLoading markdown="# 🧠 Refining..." />;

  const md = `## Original\n\n${result.original}\n\n## Refined\n\n${result.refined}\n\n## Diff\n\n${result.diff}`;
  return (
    <Detail
      markdown={md}
      actions={
        <ActionPanel>
          <Action
            title="Accept"
            onAction={async () => {
              await Clipboard.paste(result.refined);
              pop();
              await showHUD("✨ Applied");
            }}
          />
          <Action
            title="Cancel"
            shortcut={{ modifiers: ["cmd"], key: "." }}
            onAction={pop}
          />
        </ActionPanel>
      }
    />
  );
}
