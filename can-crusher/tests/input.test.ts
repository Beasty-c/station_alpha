import { describe, expect, it } from 'vitest';
import {
  aimKeyFor,
  applyKeyboardAim,
  clampAim,
  emptyKeys,
  isStompKey,
  KEYBOARD_SPEED,
  MAX_FRAME_STEP,
  pointerToNdc,
} from '../src/domain/input';
import { AIM_LIMIT_X, AIM_LIMIT_Z } from '../src/domain/constants';

const rect = { left: 0, top: 0, width: 800, height: 600 };

describe('pointer to normalized device coordinates', () => {
  it('puts the middle of the canvas at the origin', () => {
    expect(pointerToNdc(400, 300, rect)).toEqual({ x: 0, y: 0 });
  });

  it('maps the corners to the corners of the clip cube', () => {
    expect(pointerToNdc(0, 0, rect)).toEqual({ x: -1, y: 1 });
    expect(pointerToNdc(800, 600, rect)).toEqual({ x: 1, y: -1 });
  });

  it('accounts for a canvas that is not at the origin', () => {
    const offsetRect = { left: 120, top: 40, width: 800, height: 600 };
    expect(pointerToNdc(520, 340, offsetRect)).toEqual({ x: 0, y: 0 });
  });

  it('clamps a pointer dragged outside the canvas', () => {
    expect(pointerToNdc(-4000, 9000, rect)).toEqual({ x: -1, y: -1 });
  });

  it('returns the centre for a degenerate rect or a coordinate-less event', () => {
    expect(pointerToNdc(10, 10, { left: 0, top: 0, width: 0, height: 0 })).toEqual({ x: 0, y: 0 });
    expect(pointerToNdc(NaN, NaN, rect)).toEqual({ x: 0, y: 0 });
  });
});

describe('keyboard aim', () => {
  it('moves at the documented speed', () => {
    const moved = applyKeyboardAim({ x: 0, z: 0 }, { ...emptyKeys(), right: true }, 0.05);
    expect(moved.x).toBeCloseTo(KEYBOARD_SPEED * 0.05, 6);
    expect(moved.z).toBe(0);
  });

  it('caps the step so a backgrounded tab does not teleport the foot', () => {
    const moved = applyKeyboardAim({ x: 0, z: 0 }, { ...emptyKeys(), right: true }, 5);
    expect(moved.x).toBeCloseTo(KEYBOARD_SPEED * MAX_FRAME_STEP, 6);
  });

  it('does not let diagonals travel faster than the cardinals', () => {
    const straight = applyKeyboardAim({ x: 0, z: 0 }, { ...emptyKeys(), right: true }, 0.1);
    const diagonal = applyKeyboardAim(
      { x: 0, z: 0 },
      { ...emptyKeys(), right: true, down: true },
      0.1,
    );
    expect(Math.hypot(diagonal.x, diagonal.z)).toBeCloseTo(Math.abs(straight.x), 6);
  });

  it('cancels opposing keys', () => {
    const aim = applyKeyboardAim({ x: 1, z: 1 }, { left: true, right: true, up: true, down: true }, 0.1);
    expect(aim).toEqual({ x: 1, z: 1 });
  });

  it('clamps at the edge of the slab and swallows silly frame times', () => {
    const aim = applyKeyboardAim({ x: AIM_LIMIT_X, z: 0 }, { ...emptyKeys(), right: true }, 99);
    expect(aim.x).toBe(AIM_LIMIT_X);
    expect(applyKeyboardAim({ x: 0, z: 0 }, { ...emptyKeys(), right: true }, NaN).x).toBe(0);
  });

  it('recognises both arrows and WASD', () => {
    expect(aimKeyFor('ArrowLeft')).toBe('left');
    expect(aimKeyFor('KeyA')).toBe('left');
    expect(aimKeyFor('ArrowRight')).toBe('right');
    expect(aimKeyFor('KeyD')).toBe('right');
    expect(aimKeyFor('ArrowUp')).toBe('up');
    expect(aimKeyFor('KeyW')).toBe('up');
    expect(aimKeyFor('ArrowDown')).toBe('down');
    expect(aimKeyFor('KeyS')).toBe('down');
    expect(aimKeyFor('KeyQ')).toBeNull();
  });

  it('recognises the stomp keys', () => {
    expect(isStompKey('Space')).toBe(true);
    expect(isStompKey('Enter')).toBe(true);
    expect(isStompKey('NumpadEnter')).toBe(true);
    expect(isStompKey('KeyM')).toBe(false);
  });
});

describe('clampAim', () => {
  it('keeps the aim on the slab', () => {
    expect(clampAim({ x: 99, z: -99 })).toEqual({ x: AIM_LIMIT_X, z: -AIM_LIMIT_Z });
  });

  it('replaces NaN with the near edge rather than propagating it', () => {
    const aim = clampAim({ x: NaN, z: NaN });
    expect(Number.isFinite(aim.x)).toBe(true);
    expect(Number.isFinite(aim.z)).toBe(true);
  });
});
