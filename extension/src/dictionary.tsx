import {
  List,
  ActionPanel,
  Action,
  Icon,
  Clipboard,
  closeMainWindow,
  getFrontmostApplication,
  showHUD,
} from "@raycast/api";
import { useState } from "react";
import { api } from "./lib/api";
import type { Candidate, DictionaryResponse } from "./lib/types";

export default function Command() {
  const [q, setQ] = useState("");
  const [result, setResult] = useState<DictionaryResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = async () => {
    if (!q.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const r = await api.dictionary(q);
      setResult(r);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  };

  const pickWord = async (cand: Candidate, idx: number) => {
    try {
      const app = await getFrontmostApplication();
      await api.pick(q, result?.candidates ?? [], idx, app.name);
      await closeMainWindow({ clearRootSearch: true });
      await Clipboard.paste(cand.word);
    } catch (e) {
      await showHUD(`❌ ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  return (
    <List
      searchText={q}
      onSearchTextChange={setQ}
      isLoading={loading}
      searchBarPlaceholder="Describe the word (English or Hebrew)..."
      throttle
      actions={
        <ActionPanel>
          <Action title="Search" onAction={search} />
        </ActionPanel>
      }
    >
      {error ? (
        <List.EmptyView title="Error" description={error} icon={Icon.Warning} />
      ) : result && result.candidates.length === 0 ? (
        <List.EmptyView
          title="No candidates"
          description="Try rephrasing the query."
        />
      ) : null}
      {result?.candidates.map((c, idx) => (
        <List.Item
          key={idx}
          title={c.word}
          subtitle={c.example}
          accessories={[
            { text: c.register },
            ...(c.confidence === "low"
              ? [{ icon: Icon.Warning, text: "low confidence" }]
              : []),
          ]}
          actions={
            <ActionPanel>
              <Action title="Paste" onAction={() => pickWord(c, idx)} />
              <Action.CopyToClipboard title="Copy Word" content={c.word} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
