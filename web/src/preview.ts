import type { Connection, ConnectionState } from './connection';
import type { Payload, RemoteState } from './protocol';
import { LocalizedError, t, type TextKey } from './i18n';

export const previewScenes = {
  browser: 'sceneBrowser',
  single: 'sceneSingle',
  first: 'sceneFirst',
  last: 'sceneLast',
  iina: 'sceneIina',
  generic: 'sceneGeneric',
  paused: 'scenePaused',
  locked: 'sceneLocked',
} as const;
export type PreviewScene = keyof typeof previewScenes;

export function readPreviewScene(search: string): PreviewScene | undefined {
  const scene = new URLSearchParams(search).get('preview');
  return scene && Object.hasOwn(previewScenes, scene) ? scene as PreviewScene : undefined;
}

function previewState(scene: PreviewScene): ConnectionState {
  const layout = scene === 'iina' ? 'iina' : scene === 'generic' ? 'generic' : 'browser';
  const remote: RemoteState = {
    appName: layout === 'browser' ? 'Chrome' : layout === 'iina' ? 'IINA' : 'Mac',
    bundleId: layout === 'browser' ? 'com.google.Chrome' : layout === 'iina' ? 'com.colliderli.iina' : '',
    layout, locked: scene === 'locked', accessibility: true, paused: scene === 'paused', captureAvailable: false,
  };
  if (['browser', 'first', 'last'].includes(scene)) {
    remote.episodeControls = { previous: scene !== 'first', next: scene !== 'last' };
  }
  return { connected: true, authenticated: true, reconnectRequired: false, remote };
}

type FrontendConnection = Pick<Connection,
  'state' | 'onChange' | 'onDisconnect' | 'connect' | 'dispose' | 'send' | 'request'
  | 'resume' | 'clearError' | 'reconnectNow' | 'paired' | 'enabled'>;

/** Development-only fixtures: never create a socket or read/write pairing credentials. */
export class PreviewConnection implements FrontendConnection {
  state: ConnectionState;
  private action?: { key: TextKey; action?: TextKey | string };
  get lastAction() {
    if (!this.action) return '';
    const label = this.action.action;
    return t(this.action.key, { action: label && Object.hasOwn(actionLabels, label) ? t(actionLabels[label]) : label ?? '' });
  }
  onChange: (state: ConnectionState) => void = () => {};
  onDisconnect: () => void = () => {};
  private disposed = false;
  constructor(public scene: PreviewScene) { this.state = previewState(scene); }
  get paired() { return false; }
  get enabled() {
    return !this.disposed && this.state.authenticated && !!this.state.remote
      && !this.state.remote.locked && !this.state.remote.paused;
  }
  connect() { if (!this.disposed) this.onChange(this.state); }
  setScene(scene: PreviewScene) {
    if (this.disposed || !Object.hasOwn(previewScenes, scene)) return;
    this.scene = scene; this.action = undefined; this.state = previewState(scene);
    this.onDisconnect();
    this.onChange(this.state);
  }
  send(type: string, payload: Payload = {}) {
    if (!this.enabled) return false;
    if (type === 'media.command' && payload.action === 'previousEpisode'
        && !this.state.remote?.episodeControls?.previous) return false;
    if (type === 'media.command' && payload.action === 'nextEpisode'
        && !this.state.remote?.episodeControls?.next) return false;
    if (type === 'input.text.insert') this.action = { key: 'previewText' };
    else if (payload.action) this.action = { key: 'previewAction', action: payload.action };
    else if (type === 'input.pointer.click') this.action = { key: 'previewClick' };
    else return true; // Motion need not trigger a render every frame.
    this.state = { ...this.state };
    this.onChange(this.state);
    return true;
  }
  request(type: string, payload: Payload): Promise<void> {
    return this.send(type, payload) ? Promise.resolve() : Promise.reject(new LocalizedError('previewUnavailable'));
  }
  resume = () => {};
  reconnectNow() { this.connect(); }
  clearError() {}
  dispose() { this.disposed = true; this.onDisconnect(); }
}

const actionLabels: Record<string, TextKey> = {
  playPause: 'playPause', previousEpisode: 'previousEpisode', nextEpisode: 'nextEpisode',
  seekBackward: 'seekBackward', seekForward: 'seekForward', volumeDown: 'volumeDown', volumeUp: 'volumeUp',
  mute: 'mute', fullscreen: 'fullscreen', back: 'back', forward: 'forward', reload: 'reload',
  switchApp: 'switchApp', address: 'address', previousTab: 'previousTab', nextTab: 'nextTab',
  escape: 'escape', enter: 'enter',
};
