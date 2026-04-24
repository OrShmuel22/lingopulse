import fetch from "node-fetch";
import type {
  ApiResponse,
  RefineResponse,
  UndoResponse,
  DictionaryResponse,
  PickResponse,
  StatusResponse,
  Candidate,
  CaptureStyleResponse,
  Tone,
} from "./types";

const HOST = "127.0.0.1";
const DEFAULT_PORT = 17823;

function baseUrl(): string {
  return `http://${HOST}:${DEFAULT_PORT}`;
}

async function call<T>(path: string, body?: unknown): Promise<T> {
  const url = `${baseUrl()}${path}`;
  const init: Parameters<typeof fetch>[1] =
    body !== undefined
      ? {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        }
      : { method: "GET" };
  const res = await fetch(url, init);
  const raw = (await res.json()) as ApiResponse<T>;
  if (!raw.ok) throw new Error(raw.error);
  return raw.data;
}

export const api = {
  status: () => call<StatusResponse>("/status"),
  config: () => call<Record<string, unknown>>("/config"),
  refine: (selection: string, app: string, tone_override?: Tone) =>
    call<RefineResponse>("/refine", { selection, app, tone_override }),
  undo: (ring_id?: number | string) =>
    call<UndoResponse>(
      "/refine/undo",
      ring_id !== undefined ? { ring_id } : {},
    ),
  dictionary: (query: string) =>
    call<DictionaryResponse>("/dictionary", { query }),
  pick: (
    query: string,
    candidates: Candidate[],
    picked_index: number,
    app: string,
  ) =>
    call<PickResponse>("/dictionary/pick", {
      query,
      candidates,
      picked_index,
      app,
    }),
  captureStyle: (text: string, app: string) =>
    call<CaptureStyleResponse>("/capture_style", { text, app }),
};
