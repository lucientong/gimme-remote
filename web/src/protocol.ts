export interface RemoteState {
  appName: string;
  bundleId: string;
  layout: 'iina' | 'browser' | 'generic';
  locked: boolean;
  accessibility: boolean;
  paused: boolean;
  captureAvailable: boolean;
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
export const errors: Record<string, string> = {
  unauthorized: '配对已失效，请重新配对',
  invalidPairingCode: '配对码错误或已过期，请在 Mac 上更新',
  rateLimited: '操作过于频繁，请稍后重新连接',
  macLocked: 'Mac 已锁定，请在 Mac 上解锁',
  accessibilityRequired: '请在 Mac 菜单栏授权辅助功能',
  servicePaused: '遥控已暂停，请在 Mac 菜单栏恢复',
  keychainUnavailable: 'Mac 钥匙串不可用，请解锁后重试',
  deviceLimit: '配对设备已满，请在 Mac 菜单栏撤销旧配对',
  pointerBusy: '另一台手机正在拖动，请稍后再试',
  protocolVersion: '协议版本不匹配，请刷新页面',
  inputFailed: 'Mac 未能发送输入，请重试',
  invalidPayload: '指令无效，请刷新页面后重试',
  unsupportedMessage: 'Mac 端版本不支持该操作，请更新 Gimme Remote',
  messageTooLarge: '内容过长，请分段发送',
};

/** Home Screen web apps have storage separate from Safari, so they pair on their own. */
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
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* Safari storage can be disabled. */ }
}
