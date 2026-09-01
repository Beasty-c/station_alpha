/**
 * The can's geometry, as pure maths.
 *
 * The renderer owns the buffers; this module owns where every vertex goes.
 * Keeping it here means the deformation can be asserted on directly — final
 * height, symmetry, which way the fold leans — without spinning up WebGL.
 */

import { CAN_HEIGHT, CAN_RADIUS, MIN_HEIGHT_RATIO } from './constants';
import { clamp01, lerp } from './math';
import type { CrushOutcome } from './types';

export interface Point3 {
  x: number;
  y: number;
  z: number;
}

/** Number of concertina folds a fully crushed can shows. */
const RIPPLES = 5;
const RIPPLE_DEPTH = 0.17;
const BULGE_DEPTH = 0.34;
const PINCH_DEPTH = 0.3;

/**
 * The pristine silhouette: a straight body with a chamfered base and a
 * shouldered neck, normalized so the widest part is exactly CAN_RADIUS.
 */
export function canBaseRadius(v: number): number {
  const t = clamp01(v);
  if (t < 0.05) return CAN_RADIUS * lerp(0.82, 1, t / 0.05);
  if (t > 0.86) {
    const s = (t - 0.86) / 0.14;
    // Shoulder, then the narrow rim.
    return CAN_RADIUS * lerp(1, 0.63, s * s * (3 - 2 * s));
  }
  return CAN_RADIUS;
}

/** Height of the can at a given animation progress, in world units. */
export function crushedHeight(outcome: CrushOutcome, progress: number): number {
  const p = clamp01(progress);
  return CAN_HEIGHT * lerp(1, outcome.heightRatio, p);
}

/** 0 for an untouched can, 1 for one squashed as flat as the model allows. */
export function crushAmount(outcome: CrushOutcome, progress: number): number {
  const h = lerp(1, outcome.heightRatio, clamp01(progress));
  return clamp01((1 - h) / (1 - MIN_HEIGHT_RATIO));
}

/**
 * Places one vertex of the can.
 *
 * `theta` runs around the can, `v` runs 0 (base) to 1 (lid). The result is in
 * the can's own space, with the base sitting on y = 0.
 */
export function deformCanPoint(
  theta: number,
  v: number,
  outcome: CrushOutcome,
  progress: number,
): Point3 {
  const p = clamp01(progress);
  const t = clamp01(v);
  const height = crushedHeight(outcome, p);
  const crush = crushAmount(outcome, p);

  const cos = Math.cos(theta);
  const sin = Math.sin(theta);

  // How far this vertex faces the direction the can is escaping towards.
  const facing = cos * outcome.escapeDir.x + sin * outcome.escapeDir.z;

  let radius = canBaseRadius(t);
  // Concertina: an even crush pleats the body.
  radius *= 1 + RIPPLE_DEPTH * crush * (1 - outcome.asymmetry * 0.7) * Math.sin(t * Math.PI * RIPPLES);
  // A clean crush pushes the waist out; a folded one does not.
  radius *= 1 + BULGE_DEPTH * outcome.bulge * crush * Math.sin(Math.PI * t);
  // A lopsided hit caves in the pressed side and swells the far side.
  radius *= 1 + PINCH_DEPTH * outcome.asymmetry * crush * facing;

  // The body hinges at the buckle and the part above it folds over.
  const hinge = clamp01(outcome.buckleHeight);
  const phi = outcome.foldAngle * p;
  const above = Math.max(0, t - hinge);
  const segment = above * height;
  const bendCos = Math.cos(phi);
  const bendSin = Math.sin(phi);

  const spineY = Math.min(t, hinge) * height + segment * bendCos;
  const spineLateral = segment * bendSin;

  // Rings stay horizontal but foreshorten along the fold, which reads as a
  // squashed tube rather than a stack of discs.
  const squash = lerp(1, bendCos, above / Math.max(1e-6, 1 - hinge));
  const alongX = outcome.escapeDir.x;
  const alongZ = outcome.escapeDir.z;
  const ringX = cos * radius;
  const ringZ = sin * radius;
  const alongLen = ringX * alongX + ringZ * alongZ;
  const shrink = alongLen * (squash - 1);

  return {
    x: ringX + shrink * alongX + spineLateral * alongX,
    y: spineY,
    z: ringZ + shrink * alongZ + spineLateral * alongZ,
  };
}

/** Where the crushed can ends up on the slab, relative to where it started. */
export function canDisplacement(outcome: CrushOutcome, progress: number): Point3 {
  const p = clamp01(progress);
  const slide = outcome.launch * 1.9 * p * (2 - p);
  return {
    x: outcome.escapeDir.x * slide,
    y: 0,
    z: outcome.escapeDir.z * slide,
  };
}
