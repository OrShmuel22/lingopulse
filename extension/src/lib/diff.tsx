import { Detail } from "@raycast/api";

export function DiffDetail({
  original,
  refined,
  diff,
}: {
  original: string;
  refined: string;
  diff: string;
}) {
  const md = `## Original\n\n${original}\n\n## Refined\n\n${refined}\n\n## Diff\n\n${diff}\n`;
  return <Detail markdown={md} />;
}
