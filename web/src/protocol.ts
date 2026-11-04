export interface RemoteState {
  appName: string;
  bundleId: string;
  layout: 'iina' | 'browser' | 'generic';
  locked: boolean;
  accessibility: boolean;
  paused: boolean;
  captureAvailable: boolean;
  episodeControls?: { previous?: boolean; next?: boolean };
}
export interface Payload {
  code?: string;
  deviceName?: string;
  token?: string;
  dx?: number;
  dy?: number;
  button?: 'left' | 'right';
  phase?: 'start' | 'end';
  text?: string;
  action?: string;
  state?: RemoteState;
  error?: string;
}
export interface Message {
  version: 1;
  type: string;
  requestId?: string;
  payload: Payload;
}
/** Home Screen web apps have storage separate from the browser, so they pair on their own. */
export function isStandalone(): boolean {
  return (navigator as Navigator & { standalone?: boolean }).standalone === true
    || (typeof matchMedia === 'function' && matchMedia('(display-mode: standalone)').matches);
}

// crypto.randomUUID is unavailable on LAN HTTP, so request IDs use a local counter.
let counter = 0;
export function requestId(): string { return `${Date.now().toString(36)}-${++counter}`; }

export function readStored<T>(key: string, fallback: T): T {
  try { const value = localStorage.getItem(key); return value ? JSON.parse(value) as T : fallback; }
  catch { return fallback; }
}
export function store(key: string, value: unknown) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* Browser storage can be disabled. */ }
}
