/** Small numeric helpers shared by the domain modules. */

export function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return value < min ? min : value > max ? max : value;
}

export function clamp01(value: number): number {
  return clamp(value, 0, 1);
}

/** Coerces anything that is not a finite number to `fallback`. */
export function finite(value: number, fallback = 0): number {
  return Number.isFinite(value) ? value : fallback;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** Maps `value` from [inMin, inMax] to [outMin, outMax], clamped at both ends. */
export function mapRange(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number,
): number {
  if (inMax === inMin) return outMin;
  const t = clamp01((finite(value, inMin) - inMin) / (inMax - inMin));
  return lerp(outMin, outMax, t);
}

/** Shrinks a magnitude by `dead`, so small errors read as no error at all. */
export function deadZone(value: number, dead: number): number {
  const v = Math.abs(finite(value));
  return v <= dead ? 0 : v - dead;
}

export function smoothstep(t: number): number {
  const x = clamp01(t);
  return x * x * (3 - 2 * x);
}

export function easeOutCubic(t: number): number {
  const x = clamp01(t);
  return 1 - Math.pow(1 - x, 3);
}

export function easeInQuad(t: number): number {
  const x = clamp01(t);
  return x * x;
}

/** Deterministic 32-bit hash, used to turn a round seed into wobble phases. */
export function hashSeed(seed: number): number {
  let h = Math.imul(finite(seed) | 0, 0x9e3779b1) >>> 0;
  h ^= h >>> 15;
  h = Math.imul(h, 0x85ebca6b) >>> 0;
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return h >>> 0;
}

/** A deterministic float in [0, 1) for the nth draw of a seed. */
export function seededUnit(seed: number, index: number): number {
  return hashSeed(seed * 0x2545f491 + index * 0x9e3779b1) / 0x100000000;
}
