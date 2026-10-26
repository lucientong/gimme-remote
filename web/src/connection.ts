import { errors, readStored, requestId, store, type Message, type Payload, type RemoteState } from './protocol';

export interface ConnectionState {
  connected: boolean;
  authenticated: boolean;
  remote?: RemoteState;
  error?: string;
}

export class Connection {
  private ws?: WebSocket;
  private token = readStored<string>('gimme.token', '');
  private reconnect?: ReturnType<typeof setTimeout>;
  private heartbeat?: ReturnType<typeof setInterval>;
  private retry = 0;
  private disposed = false;
  private lastMessage = 0;
  private pending = new Map<string, { resolve: () => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout> }>();
  state: ConnectionState = { connected: false, authenticated: false };
  onChange: (state: ConnectionState) => void = () => {};
  onDisconnect: () => void = () => {};

  private update(value: Partial<ConnectionState>) {
    this.state = { ...this.state, ...value };
    this.onChange(this.state);
  }
  connect() {
    if (this.disposed || this.ws?.readyState === WebSocket.OPEN || this.ws?.readyState === WebSocket.CONNECTING) return;
    clearTimeout(this.reconnect);
    const server = import.meta.env.VITE_REMOTE_URL || location.origin;
    const endpoint = new URL('/ws', server);
    endpoint.protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(endpoint);
    this.ws = ws;
    ws.onopen = () => {
      this.lastMessage = Date.now();
      this.update({ connected: true, authenticated: false, error: undefined });
      if (this.token) this.raw('session.authenticate', { token: this.token });
      clearInterval(this.heartbeat);
      this.heartbeat = setInterval(() => {
        if (Date.now() - this.lastMessage > 12_000) { ws.close(); return; }
        if (this.state.authenticated) this.raw('session.heartbeat', {});
      }, 4_000);
    };
    ws.onmessage = event => {
      this.lastMessage = Date.now();
      try {
        const message = JSON.parse(event.data) as Message;
        if (message.version !== 1) { this.update({ error: errors.protocolVersion }); return; }
        if (message.type === 'session.paired' || message.type === 'session.authenticated') {
          if (message.payload.token) {
            this.token = message.payload.token;
            store('gimme.token', this.token);
            history.replaceState(null, '', location.pathname + location.search);
          }
          this.retry = 0;
          this.update({ authenticated: true, error: undefined });
        }
        if (message.payload.state) this.update({ remote: message.payload.state });
        if (message.type.startsWith('error.')) {
          if (message.payload.error === 'unauthorized') {
            this.token = ''; store('gimme.token', ''); this.update({ authenticated: false });
          }
          this.update({ error: errors[message.payload.error ?? ''] ?? '操作未完成，请重试' });
        }
        if (message.requestId) {
          const pending = this.pending.get(message.requestId);
          if (pending) {
            clearTimeout(pending.timer); this.pending.delete(message.requestId);
            if (message.type.startsWith('error.')) pending.reject(new Error(this.state.error));
            else pending.resolve();
          }
        }
      } catch { this.update({ error: '收到无法识别的消息，请刷新页面' }); }
    };
    ws.onclose = () => {
      if (this.ws !== ws) return;
      clearInterval(this.heartbeat);
      this.onDisconnect();
      this.update({ connected: false, authenticated: false, remote: undefined });
      this.rejectPending('连接已断开');
      if (!this.disposed) this.reconnect = setTimeout(() => this.connect(), Math.min(8_000, 600 * 2 ** this.retry++));
    };
    ws.onerror = () => ws.close();
  }
  private raw(type: string, payload: Payload, id?: string): boolean {
    if (this.ws?.readyState !== WebSocket.OPEN) return false;
    // Drop motion if the network cannot keep up; never replay stale inputs.
    if (type === 'input.pointer.move' && this.ws.bufferedAmount > 16_384) return false;
    this.ws.send(JSON.stringify({ version: 1, type, requestId: id, payload }));
    return true;
  }
  get enabled() {
    const remote = this.state.remote;
    return this.state.connected && this.state.authenticated && !!remote
      && !remote.locked && remote.accessibility && !remote.paused;
  }
  send(type: string, payload: Payload = {}) {
    if (!this.enabled) return false;
    return this.raw(type, payload);
  }
  request(type: string, payload: Payload): Promise<void> {
    if (type !== 'session.pair' && !this.enabled) return Promise.reject(new Error('尚未连接到可控制的 Mac'));
    const id = requestId();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error('操作超时，请重试')); }, 5_000);
      this.pending.set(id, { resolve, reject, timer });
      if (!this.raw(type, payload, id)) {
        clearTimeout(timer); this.pending.delete(id); reject(new Error('连接已断开'));
      }
    });
  }
  resume = () => {
    if (document.visibilityState === 'visible') {
      if (this.ws?.readyState === WebSocket.OPEN && Date.now() - this.lastMessage > 8_000) this.ws.close();
      else this.connect();
    } else { this.onDisconnect(); }
  };
  clearError() { this.update({ error: undefined }); }
  private rejectPending(reason: string) {
    for (const value of this.pending.values()) { clearTimeout(value.timer); value.reject(new Error(reason)); }
    this.pending.clear();
  }
  dispose() {
    this.disposed = true; clearTimeout(this.reconnect); clearInterval(this.heartbeat);
    this.ws?.close(); this.rejectPending('页面已关闭');
  }
}
