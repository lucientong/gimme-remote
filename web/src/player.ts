import type { RemoteState } from './protocol';

/** An older Mac sends no capabilities; absence must never imply episode support. */
export function episodeControls(remote?: RemoteState) {
  if (remote?.layout !== 'browser' || remote.locked || remote.paused || !remote.accessibility) return undefined;
  const controls = remote.episodeControls;
  if (typeof controls?.previous !== 'boolean' && typeof controls?.next !== 'boolean') return undefined;
  return controls;
}
