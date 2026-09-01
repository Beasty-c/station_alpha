/**
 * The foot's idle wobble.
 *
 * The wobble is what makes the game a skill test, so it has to be hard but
 * never unfair. Two properties are guaranteed by construction and covered by
 * tests:
 *
 *  1. It is strictly periodic, so it can be learned and anticipated.
 *  2. Twice per cycle the foot passes through *exactly* level at the top of
 *     its bob. A perfect score is therefore always available, and the round
 *     seed only shifts the phase — it never moves the ceiling.
 *
 * The sideways drift is not zeroed for the player: cancelling it with the aim
 * controls is the other half of the skill.
 */

import { mapRange, seededUnit } from './math';

/** Seconds for one full wobble cycle. */
export const WOBBLE_PERIOD = 2.4;

const OMEGA = (Math.PI * 2) / WOBBLE_PERIOD;

/** Sideways drift amplitude, world units. */
const DRIFT_X = 0.26;
/** Front/back drift amplitude, world units. */
const DRIFT_Z = 0.19;
/** Roll amplitude, radians. */
const ROLL = 0.22;
/** Pitch amplitude, radians. */
const PITCH = 0.11;

/** Hover height of the sole above the can lid, and how far it bobs. */
export const HOVER_BASE = 0.42;
export const HOVER_BOB = 0.11;

/** Power delivered at the bottom and the top of the bob. */
const POWER_MIN = 0.84;
const POWER_MAX = 1;

export interface WobbleSample {
  /** Sideways drift of the sole centre away from the aim point. */
  driftX: number;
  /** Front/back drift of the sole centre away from the aim point. */
  driftZ: number;
  /** Foot pitch about world X, radians. */
  tiltX: number;
  /** Foot roll about world Z, radians. */
  tiltZ: number;
  /** Height of the sole above the can lid. */
  hover: number;
  /** Stomp power available right now, 0.84 to 1. */
  power: number;
}

/** Turns a round seed into the phase offset for that round. */
export function phaseForSeed(seed: number): number {
  return seededUnit(seed, 7) * Math.PI * 2;
}

/**
 * Samples the wobble at time `t` seconds into the round.
 *
 * `tiltZ = ROLL·sin(θ)` and `tiltX = PITCH·sin(2θ)` share their zeros, and the
 * bob peaks at those same instants, which is what guarantees the perfect
 * window.
 */
export function wobbleAt(t: number, seed: number): WobbleSample {
  const phase = phaseForSeed(seed);
  const theta = OMEGA * (Number.isFinite(t) ? t : 0) + phase;

  const tiltZ = ROLL * Math.sin(theta);
  const tiltX = PITCH * Math.sin(2 * theta);

  const driftX = DRIFT_X * (0.75 * Math.sin(theta + 1.1) + 0.25 * Math.sin(3 * theta + 0.4));
  const driftZ = DRIFT_Z * (0.7 * Math.sin(theta + 2.7) + 0.3 * Math.sin(2 * theta + 1.9));

  const bob = Math.sin(2 * theta + Math.PI / 2);
  const hover = HOVER_BASE + HOVER_BOB * bob;
  const power = mapRange(bob, -1, 1, POWER_MIN, POWER_MAX);

  return { driftX, driftZ, tiltX, tiltZ, hover, power };
}

/** Total foot tilt magnitude at time `t`, in radians. */
export function tiltMagnitudeAt(t: number, seed: number): number {
  const w = wobbleAt(t, seed);
  return Math.hypot(w.tiltX, w.tiltZ);
}

/**
 * The next instant at or after `t` when the foot is exactly level and at the
 * top of its bob. Used by the tests, and by the tutorial's timing hint.
 */
export function nextPerfectInstant(t: number, seed: number): number {
  const phase = phaseForSeed(seed);
  // Level and at the top of the bob whenever theta is a multiple of π.
  const now = Number.isFinite(t) ? t : 0;
  const k = Math.ceil((OMEGA * now + phase) / Math.PI - 1e-9);
  return (Math.PI * k - phase) / OMEGA;
}

/**
 * How close the foot is to its perfect window right now, 0 to 1. Drives the
 * subtle glow on the foot so the player can read the rhythm.
 */
export function windowCloseness(t: number, seed: number): number {
  const tilt = tiltMagnitudeAt(t, seed);
  const w = wobbleAt(t, seed);
  const level = 1 - Math.min(1, tilt / 0.08);
  const high = mapRange(w.hover, HOVER_BASE, HOVER_BASE + HOVER_BOB, 0, 1);
  return level * high;
}
