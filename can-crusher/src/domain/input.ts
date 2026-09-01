/**
 * Input normalization.
 *
 * Everything the player can do — drag, move the mouse, hold a key, tilt a
 * gamepad stick if one ever turns up — is funnelled into a single aim point on
 * the ground plane. Kept free of DOM types so it can be tested in Node.
 */

import { AIM_LIMIT_X, AIM_LIMIT_Z } from './constants';
import { clamp, finite } from './math';

export interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface Aim {
  x: number;
  z: number;
}

/** Keys currently held, already resolved to directions. */
export interface AimKeys {
  left: boolean;
  right: boolean;
  up: boolean;
  down: boolean;
}

/** World units the keyboard moves the aim per second. */
export const KEYBOARD_SPEED = 2.4;

/**
 * Longest frame the aim will integrate over. A backgrounded tab can hand back
 * a multi-second delta; without the cap the foot would teleport on return.
 */
export const MAX_FRAME_STEP = 0.1;

/** Clamps an aim point to the reachable area of the slab. */
export function clampAim(aim: Aim): Aim {
  return {
    x: clamp(finite(aim?.x), -AIM_LIMIT_X, AIM_LIMIT_X),
    z: clamp(finite(aim?.z), -AIM_LIMIT_Z, AIM_LIMIT_Z),
  };
}

/** A pointer position in normalized device coordinates, -1 to 1 on both axes. */
export interface Ndc {
  x: number;
  y: number;
}

/**
 * Maps a pointer position inside the canvas to normalized device coordinates,
 * which is what the camera needs to cast a ray at the slab.
 *
 * A degenerate rect (a detached canvas, a zero-sized element) or a synthetic
 * event with no coordinates returns the centre of the view rather than NaN.
 */
export function pointerToNdc(clientX: number, clientY: number, rect: Rect): Ndc {
  const width = finite(rect?.width, 0);
  const height = finite(rect?.height, 0);
  if (width <= 0 || height <= 0) return { x: 0, y: 0 };
  if (!Number.isFinite(clientX) || !Number.isFinite(clientY)) return { x: 0, y: 0 };

  return {
    x: clamp(((clientX - finite(rect.left)) / width) * 2 - 1, -1, 1),
    y: clamp(1 - ((clientY - finite(rect.top)) / height) * 2, -1, 1),
  };
}

/** Applies one frame of held-key movement to the aim point. */
export function applyKeyboardAim(aim: Aim, keys: AimKeys, dt: number): Aim {
  const step = KEYBOARD_SPEED * clamp(finite(dt), 0, MAX_FRAME_STEP);
  const dx = (keys?.right ? 1 : 0) - (keys?.left ? 1 : 0);
  const dz = (keys?.down ? 1 : 0) - (keys?.up ? 1 : 0);
  if (dx === 0 && dz === 0) return clampAim(aim);
  // Diagonals should not be faster than the cardinals.
  const len = Math.hypot(dx, dz);
  return clampAim({
    x: finite(aim?.x) + (dx / len) * step,
    z: finite(aim?.z) + (dz / len) * step,
  });
}

/** Maps a keyboard event code to an aim direction, or null if it is not one. */
export function aimKeyFor(code: string): keyof AimKeys | null {
  switch (code) {
    case 'ArrowLeft':
    case 'KeyA':
      return 'left';
    case 'ArrowRight':
    case 'KeyD':
      return 'right';
    case 'ArrowUp':
    case 'KeyW':
      return 'up';
    case 'ArrowDown':
    case 'KeyS':
      return 'down';
    default:
      return null;
  }
}

/** True for the keys that trigger a stomp or start the next round. */
export function isStompKey(code: string): boolean {
  return code === 'Space' || code === 'Enter' || code === 'NumpadEnter';
}

export function emptyKeys(): AimKeys {
  return { left: false, right: false, up: false, down: false };
}
