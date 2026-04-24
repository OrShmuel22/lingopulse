import { Detail } from "@raycast/api";
import { useEffect, useState } from "react";
import { api } from "./lib/api";
import type { StatusResponse } from "./lib/types";

export default function Command() {
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .status()
      .then(setStatus)
      .catch((e: unknown) =>
        setError(e instanceof Error ? e.message : String(e)),
      );
  }, []);

  if (error)
    return (
      <Detail
        markdown={`# LingoPulse — error\n\n\`\`\`\n${error}\n\`\`\`\n\nIs the daemon running? Check \`~/Library/Logs/lingopulse-daemon.log\`.`}
      />
    );
  if (!status)
    return <Detail isLoading markdown="# LingoPulse\n\nConnecting..." />;

  return (
    <Detail
      markdown={`# LingoPulse

**Healthy:** ${status.healthy ? "✅" : "❌"}

**Model:** \`${status.model}\`

**Model loaded:** ${status.model_loaded ? "✅ warm" : "❄️ cold (first call will take longer)"}
`}
    />
  );
}
