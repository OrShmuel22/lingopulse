export interface RefineResponse {
  original: string;
  refined: string;
  diff: string;
  ring_id: number | string;
}

export interface UndoResponse {
  original: string;
}

export interface Candidate {
  word: string;
  example: string;
  register: "casual" | "neutral" | "formal" | "technical";
  confidence?: "high" | "low";
}

export interface DictionaryResponse {
  candidates: Candidate[];
  query_language: "hebrew" | "english";
}

export interface StatusResponse {
  healthy: boolean;
  model: string;
  model_loaded: boolean;
}

export interface PickResponse {
  picked_word: string;
}

export interface CaptureStyleResponse {
  saved: boolean;
}

export type Tone =
  | "Casual"
  | "Neutral"
  | "Technical"
  | "Professional"
  | "Grammar-only";

export interface ApiOk<T> {
  ok: true;
  data: T;
}
export interface ApiErr {
  ok: false;
  error: string;
}
export type ApiResponse<T> = ApiOk<T> | ApiErr;
