import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Connection } from './connection';
import type { Message, RemoteState } from './protocol';

class Socket {
  static readonly OPEN = 1;
  static readonly CONNECTING = 0;
  static instances: Socket[] = [];
  readyState = Socket.CONNECTING;
  bufferedAmount = 0;
  sent: Message[] = [];
  onopen?: () => void;
  onmessage?: (event: { data: string }) => void;
  onclose?: (event: { code: number }) => void;
  onerror?: () => void;
  close = vi.fn(() => { this.readyState = 3; });
  constructor(readonly url: URL) { Socket.instances.push(this); }
  send(text: string) { this.sent.push(JSON.parse(text)); }
  open() { this.readyState = Socket.OPEN; this.onopen?.(); }
  message(type: string, payload = {}, requestId?: string) {
    this.onmessage?.({ data: JSON.stringify({ version: 1, type, payload, requestId }) });
  }
  closed(code: number) { this.readyState = 3; this.onclose?.({ code }); }
}

const remote: RemoteState = {
  appName: 'Chrome', bundleId: 'com.google.Chrome', layout: 'browser',
  locked: false, accessibility: true, paused: false, captureAvailable: false,
};
let connection: Connection;
let stored: Map<string, string>;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(10_000);
  Socket.instances = [];
  stored = new Map();
  vi.stubGlobal('WebSocket', Socket);
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
  vi.stubGlobal('location', { origin: 'http://mac.local:9271', pathname: '/', search: '' });
  vi.stubGlobal('history', { replaceState: vi.fn() });
  vi.stubGlobal('document', { visibilityState: 'visible' });
  connection = new Connection();
});
afterEach(() => {
  connection.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function authenticate() {
  connection.connect();
  const socket = Socket.instances.at(-1)!;
  socket.open();
  socket.message('session.paired', { token: 'saved-token' });
  socket.message('state.updated', { state: remote });
  expect(connection.enabled).toBe(true);
  return socket;
}

describe('connection lifecycle', () => {
  it('waits for an explicit reconnect after Mac disconnects all, retaining pairing', () => {
    const socket = authenticate();
    const release = vi.fn();
    connection.onDisconnect = release;
    socket.closed(4000);
    expect(connection.state).toMatchObject({ connected: false, authenticated: false, reconnectRequired: true });
    expect(connection.state.remote).toBeUndefined();
    expect(connection.paired).toBe(true);
    expect(release).toHaveBeenCalledOnce();
    vi.advanceTimersByTime(30_000);
    connection.resume();
    connection.connect();
    expect(Socket.instances).toHaveLength(1);
    connection.reconnectNow();
    expect(Socket.instances).toHaveLength(2);
    const next = Socket.instances[1];
    next.open();
    expect(next.sent[0]).toMatchObject({ type: 'session.authenticate', payload: { token: 'saved-token' } });
  });

  it('automatically reconnects on server exit or a network close', () => {
    const socket = authenticate();
    socket.closed(1001);
    expect(connection.enabled).toBe(false);
    vi.advanceTimersByTime(599);
    expect(Socket.instances).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(Socket.instances).toHaveLength(2);
  });

  it('clears stale state within four seconds even without a close callback', async () => {
    const socket = authenticate();
    const pending = connection.request('input.text.insert', { text: 'hello' });
    const rejected = expect(pending).rejects.toThrow('连接已断开');
    vi.advanceTimersByTime(3_999);
    expect(connection.enabled).toBe(true);
    vi.advanceTimersByTime(1);
    await rejected;
    expect(connection.state).toMatchObject({ connected: false, authenticated: false });
    expect(socket.close).toHaveBeenCalledOnce();
    vi.advanceTimersByTime(600);
    expect(Socket.instances).toHaveLength(2);
  });

  it('ignores late state and close callbacks from the previous socket', () => {
    const previous = authenticate();
    previous.closed(1001);
    connection.reconnectNow();
    const current = Socket.instances[1];
    current.open();
    current.message('session.authenticated');
    current.message('state.updated', { state: remote });
    previous.message('state.updated', { state: { ...remote, paused: true } });
    previous.closed(4000);
    expect(connection.enabled).toBe(true);
    expect(connection.state.reconnectRequired).toBe(false);
  });

  it('disables paused controls while keeping the authenticated connection available for resume', () => {
    const socket = authenticate();
    socket.message('state.updated', { state: { ...remote, paused: true } });
    expect(connection.state.authenticated).toBe(true);
    expect(connection.enabled).toBe(false);
    expect(connection.send('media.command', { action: 'playPause' })).toBe(false);
    socket.message('state.updated', { state: remote });
    expect(connection.enabled).toBe(true);
    expect(Socket.instances).toHaveLength(1);
  });

  it('reconnects promptly after returning to a stale page', () => {
    authenticate();
    vi.setSystemTime(12_001);
    connection.resume();
    expect(connection.state.connected).toBe(false);
    expect(Socket.instances).toHaveLength(2);
  });

  it('leaves time to enter a pairing code before the initial idle timeout', () => {
    connection.connect();
    Socket.instances[0].open();
    vi.advanceTimersByTime(10_000);
    expect(connection.state.connected).toBe(true);
    expect(Socket.instances).toHaveLength(1);
  });

  it('rejects pending inputs immediately on disconnect and cleans up disposal timers', async () => {
    const socket = authenticate();
    const rejected = expect(connection.request('input.text.insert', { text: 'hello' })).rejects.toThrow('连接已断开');
    socket.closed(4000);
    await rejected;
    connection.dispose();
    vi.advanceTimersByTime(30_000);
    expect(Socket.instances).toHaveLength(1);
    expect(vi.getTimerCount()).toBe(0);
  });
});
