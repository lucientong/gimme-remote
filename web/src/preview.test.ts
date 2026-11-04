import { afterEach, expect, it, vi } from 'vitest';
import { PreviewConnection, readPreviewScene } from './preview';

afterEach(() => vi.unstubAllGlobals());

it('requires an explicit supported preview scene', () => {
  expect(readPreviewScene('')).toBeUndefined();
  expect(readPreviewScene('?preview=nope')).toBeUndefined();
  expect(readPreviewScene('?preview=browser')).toBe('browser');
  expect(readPreviewScene('?preview=first')).toBe('first');
});

it('runs controls without sockets or pairing credential access', async () => {
  vi.stubGlobal('WebSocket', vi.fn(() => { throw new Error('Preview opened a socket'); }));
  const read = vi.fn(() => { throw new Error('Preview read credentials'); });
  const write = vi.fn(() => { throw new Error('Preview wrote credentials'); });
  vi.stubGlobal('localStorage', { getItem: read, setItem: write });
  const preview = new PreviewConnection('browser');
  preview.connect();
  expect(preview.enabled).toBe(true);
  expect(preview.send('media.command', { action: 'nextEpisode' })).toBe(true);
  expect(preview.lastAction).toContain('下一集');
  await preview.request('input.text.insert', { text: 'test' });
  expect(preview.lastAction).toContain('未发送到 Mac');
  expect(WebSocket).not.toHaveBeenCalled();
  expect(read).not.toHaveBeenCalled();
  expect(write).not.toHaveBeenCalled();
});

it('switches layout and episode capabilities, cancelling active gestures', () => {
  const preview = new PreviewConnection('browser');
  preview.onDisconnect = vi.fn();
  preview.onChange = vi.fn();
  expect(preview.state.remote?.episodeControls).toEqual({ previous: true, next: true });
  preview.setScene('single');
  expect(preview.state.remote?.episodeControls).toBeUndefined();
  preview.setScene('iina');
  expect(preview.state.remote?.layout).toBe('iina');
  preview.setScene('generic');
  expect(preview.state.remote?.layout).toBe('generic');
  expect(preview.onDisconnect).toHaveBeenCalledTimes(3);
  expect(preview.onChange).toHaveBeenCalledTimes(3);
});

it('respects first/last episode boundaries and blocked states', () => {
  const preview = new PreviewConnection('first');
  expect(preview.send('media.command', { action: 'previousEpisode' })).toBe(false);
  expect(preview.send('media.command', { action: 'nextEpisode' })).toBe(true);
  preview.setScene('last');
  expect(preview.send('media.command', { action: 'nextEpisode' })).toBe(false);
  preview.setScene('paused');
  expect(preview.enabled).toBe(false);
  preview.setScene('locked');
  expect(preview.enabled).toBe(false);
  preview.setScene('browser');
  expect(preview.enabled).toBe(true);
  preview.dispose();
  expect(preview.send('media.command', { action: 'playPause' })).toBe(false);
});
