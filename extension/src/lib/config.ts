import { api } from "./api";

let _cached: Record<string, unknown> | null = null;

export async function getConfig(): Promise<Record<string, unknown>> {
  if (_cached) return _cached;
  _cached = await api.config();
  return _cached;
}
