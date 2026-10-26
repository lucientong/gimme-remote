import { afterEach, describe, expect, it, vi } from 'vitest';
import { RepeatButton, TouchpadGesture } from './gestures';
import Ajv from 'ajv';
import schema from '../../shared/protocol.schema.json';
import { requestId } from './protocol';

afterEach(() => vi.useRealTimers());
describe('touchpad', () => {
  it('distinguishes single click, two-finger right click and scrolling', () => {
    const emit = vi.fn();
    const gesture = new TouchpadGesture(emit);
    gesture.down(1, 10, 10, 0); gesture.up(1, 80);
    expect(emit).toHaveBeenLastCalledWith('input.pointer.click', { button: 'left' });
    gesture.down(1, 10, 10, 100); gesture.down(2, 30, 10, 100);
    gesture.up(1, 150); gesture.up(2, 150);
    expect(emit).toHaveBeenLastCalledWith('input.pointer.click', { button: 'right' });
    emit.mockClear();
    gesture.down(1, 0, 0, 200); gesture.down(2, 30, 0, 200);
    gesture.move(1, 0, 40); gesture.move(2, 30, 40); gesture.flush();
    expect(emit).toHaveBeenLastCalledWith('input.pointer.scroll', { dx: 0, dy: 40 });
    gesture.up(1, 300); gesture.move(2, 30, 80); gesture.up(2, 350);
    expect(emit).toHaveBeenCalledTimes(1);
  });
  it('ends long-press drag on cancellation and drops buffered movement', () => {
    vi.useFakeTimers();
    const emit = vi.fn(), gesture = new TouchpadGesture(emit);
    gesture.down(1, 0, 0);
    vi.advanceTimersByTime(400);
    expect(emit).toHaveBeenCalledWith('input.pointer.drag', { phase: 'start' });
    gesture.move(1, 20, 10); gesture.cancel(); gesture.flush();
    expect(emit).toHaveBeenLastCalledWith('input.pointer.drag', { phase: 'end' });
    expect(emit).toHaveBeenCalledTimes(2);
  });
  it('bounds accelerated movement to the protocol limits', () => {
    const emit = vi.fn(), gesture = new TouchpadGesture(emit);
    gesture.down(1, 0, 0); gesture.move(1, 1000, -1000); gesture.flush();
    expect(emit).toHaveBeenLastCalledWith('input.pointer.move', { dx: 500, dy: -500 });
    gesture.cancel();
  });
});
it('long-press repeats stop permanently on release', () => {
  vi.useFakeTimers();
  const invoke = vi.fn(), repeat = new RepeatButton(invoke);
  repeat.start(); vi.advanceTimersByTime(1000);
  const before = invoke.mock.calls.length;
  expect(before).toBeGreaterThan(1);
  repeat.stop(); vi.advanceTimersByTime(2000);
  expect(invoke).toHaveBeenCalledTimes(before);
});
it('uses request IDs on insecure LAN HTTP without crypto.randomUUID', () => {
  expect(requestId()).not.toEqual(requestId());
});
it('shared schema rejects arbitrary commands and accepts actual input envelopes', () => {
  const validate = new Ajv().compile(schema);
  expect(validate({ version: 1, type: 'input.pointer.move', payload: { dx: 10, dy: -2 } })).toBe(true);
  expect(validate({ version: 1, type: 'media.command', payload: { action: 'volumeUp' } })).toBe(true);
  expect(validate({ version: 1, type: 'input.text.insert', payload: { text: '流浪地球 🌏' } })).toBe(true);
  expect(validate({ version: 1, type: 'shell.exec', payload: {} })).toBe(false);
  expect(validate({ version: 1, type: 'input.pointer.move', payload: { dx: 501, dy: 0 } })).toBe(false);
});
