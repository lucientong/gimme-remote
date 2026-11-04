import { expect, it } from 'vitest';
import Ajv from 'ajv';
import schema from '../../shared/protocol.schema.json';
import { episodeControls } from './player';
import type { RemoteState } from './protocol';

const remote: RemoteState = {
  appName: 'Chrome', bundleId: 'com.google.Chrome', layout: 'browser',
  locked: false, accessibility: true, paused: false, captureAvailable: false,
};

it('hides episodes without explicit current-player capabilities, including older Macs', () => {
  expect(episodeControls()).toBeUndefined();
  expect(episodeControls(remote)).toBeUndefined();
  expect(episodeControls({ ...remote, episodeControls: {} })).toBeUndefined();
});

it('preserves independent presence and disabled boundaries', () => {
  expect(episodeControls({ ...remote, episodeControls: { next: true } })).toEqual({ next: true });
  expect(episodeControls({ ...remote, episodeControls: { previous: false, next: true } }))
    .toEqual({ previous: false, next: true });
  expect(episodeControls({ ...remote, episodeControls: { previous: true, next: false } }))
    .toEqual({ previous: true, next: false });
});

it('drops capabilities when the target is not an available browser', () => {
  const series = { ...remote, episodeControls: { previous: true, next: true } };
  for (const state of [{ ...series, layout: 'iina' as const }, { ...series, paused: true },
    { ...series, locked: true }, { ...series, accessibility: false }]) {
    expect(episodeControls(state)).toBeUndefined();
  }
  expect(episodeControls(series)).toBeDefined();
  expect(episodeControls(remote)).toBeUndefined();
});

it('validates old and new states while rejecting malformed capability values', () => {
  const validate = new Ajv().compile(schema);
  const message = (state: unknown) => ({ version: 1, type: 'state.updated', payload: { state } });
  expect(validate(message(remote))).toBe(true);
  expect(validate(message({ ...remote, episodeControls: { next: true, previous: false } }))).toBe(true);
  expect(validate(message({ ...remote, episodeControls: { next: 'yes' } }))).toBe(false);
});
