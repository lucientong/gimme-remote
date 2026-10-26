import type { Payload } from './protocol';

type Point = { x: number; y: number };
export type Emit = (type: string, payload: Payload) => void;

export class TouchpadGesture {
  private points = new Map<number, Point>();
  private startTime = 0;
  private distance = 0;
  private twoFinger = false;
  private drag = false;
  private hold?: ReturnType<typeof setTimeout>;
  private dx = 0;
  private dy = 0;
  private mode: 'move' | 'scroll' = 'move';
  speed = 1.3;
  acceleration = true;
  constructor(private emit: Emit) {}

  down(id: number, x: number, y: number, now = performance.now()) {
    if (this.points.size === 0) {
      this.startTime = now; this.distance = 0; this.twoFinger = false;
      this.hold = setTimeout(() => {
        if (this.points.size === 1 && this.distance < 7) {
          this.drag = true; this.emit('input.pointer.drag', { phase: 'start' });
        }
      }, 380);
    }
    this.points.set(id, { x, y });
    if (this.points.size > 1) { this.twoFinger = true; clearTimeout(this.hold); }
  }
  move(id: number, x: number, y: number) {
    const previous = this.points.get(id);
    if (!previous) return;
    const dx = x - previous.x, dy = y - previous.y;
    this.points.set(id, { x, y });
    this.distance += Math.hypot(dx, dy);
    if (this.distance > 7) clearTimeout(this.hold);
    const mode = this.points.size > 1 ? 'scroll' : 'move';
    // Lifting the first of two fingers must not suddenly move the cursor.
    if (this.twoFinger && mode === 'move' && !this.drag) return;
    if (mode !== this.mode) this.flush();
    this.mode = mode;
    const gain = mode === 'scroll' ? 0.5 : this.speed * (this.acceleration ? 1 + Math.min(Math.hypot(dx, dy) / 35, 1) : 1);
    this.dx += dx * gain; this.dy += dy * gain;
  }
  up(id: number, now = performance.now()) {
    this.points.delete(id);
    if (this.points.size > 0) return;
    clearTimeout(this.hold); this.flush();
    if (this.drag) { this.emit('input.pointer.drag', { phase: 'end' }); this.drag = false; }
    else if (now - this.startTime < 330 && this.distance < 10) {
      this.emit('input.pointer.click', { button: this.twoFinger ? 'right' : 'left' });
    }
  }
  flush() {
    if (this.dx || this.dy) {
      this.emit(`input.pointer.${this.mode}`, {
        dx: Math.max(-500, Math.min(500, this.dx)), dy: Math.max(-500, Math.min(500, this.dy)),
      });
      this.dx = 0; this.dy = 0;
    }
  }
  cancel() {
    clearTimeout(this.hold);
    if (this.drag) this.emit('input.pointer.drag', { phase: 'end' });
    this.drag = false; this.points.clear(); this.dx = 0; this.dy = 0;
  }
}

export class RepeatButton {
  private delay?: ReturnType<typeof setTimeout>;
  private interval?: ReturnType<typeof setInterval>;
  constructor(private invoke: () => void) {}
  start() {
    this.stop(); this.invoke();
    this.delay = setTimeout(() => { this.interval = setInterval(this.invoke, 160); }, 400);
  }
  stop = () => { clearTimeout(this.delay); clearInterval(this.interval); };
}
