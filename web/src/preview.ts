import type { Connection, ConnectionState } from './connection';
import type { Payload, RemoteState } from './protocol';

export const previewScenes = {
  browser: 'Chrome · 分集视频',
  single: 'Chrome · 单视频',
  first: 'Chrome · 第一集',
  last: 'Chrome · 最后一集',
  iina: 'IINA',
  generic: '通用遥控',
  paused: '遥控已暂停',
  locked: 'Mac 已锁定',
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
  lastAction = '';
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
    this.scene = scene; this.lastAction = ''; this.state = previewState(scene);
    this.onDisconnect();
    this.onChange(this.state);
  }
  send(type: string, payload: Payload = {}) {
    if (!this.enabled) return false;
    if (type === 'media.command' && payload.action === 'previousEpisode'
        && !this.state.remote?.episodeControls?.previous) return false;
    if (type === 'media.command' && payload.action === 'nextEpisode'
        && !this.state.remote?.episodeControls?.next) return false;
    const labels: Record<string, string> = {
      playPause: '播放 / 暂停', previousEpisode: '上一集', nextEpisode: '下一集',
      seekBackward: '快退', seekForward: '快进', volumeDown: '音量 −', volumeUp: '音量 +',
      mute: '静音', fullscreen: '全屏', back: '网页后退', forward: '网页前进',
      reload: '刷新', switchApp: '切换应用', address: '地址栏', previousTab: '上一标签',
      nextTab: '下一标签', escape: 'Esc', enter: '回车',
    };
    if (type === 'input.text.insert') this.lastAction = '已预览文字输入，未发送到 Mac';
    else if (payload.action) this.lastAction = `已预览「${labels[payload.action] ?? payload.action}」，未发送到 Mac`;
    else if (type === 'input.pointer.click') this.lastAction = '已预览鼠标点击，未发送到 Mac';
    else return true; // Motion need not trigger a render every frame.
    this.state = { ...this.state };
    this.onChange(this.state);
    return true;
  }
  request(type: string, payload: Payload): Promise<void> {
    return this.send(type, payload) ? Promise.resolve() : Promise.reject(new Error('当前预览状态无法操作'));
  }
  resume = () => {};
  reconnectNow() { this.connect(); }
  clearError() {}
  dispose() { this.disposed = true; this.onDisconnect(); }
}
