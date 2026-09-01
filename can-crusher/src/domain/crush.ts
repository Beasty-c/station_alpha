/**
 * Turns an impact into the shape of the crushed can.
 *
 * This is the heart of the game: the same numbers that drive the mesh
 * deformation drive the score, so what the player sees is what they are
 * marked on. Nothing here is random.
 */

import {
  CAN_RADIUS,
  FOOT_HALF_LENGTH,
  FOOT_HALF_WIDTH,
  MAX_CONTACT_RADIUS,
  MAX_FOLD_ANGLE,
  MAX_TILT,
  MAX_TIP_ANGLE,
  MIN_HEIGHT_RATIO,
  CENTER_SIGMA,
  POWER_DEAD_ZONE,
  CENTER_DEAD_ZONE,
  TILT_DEAD_ZONE,
} from './constants';
import { clamp01, deadZone, finite } from './math';
import type { CrushOutcome, Impact, Vec2 } from './types';

const ZERO: Vec2 = { x: 0, z: 0 };

/** Cleans up whatever the game loop hands over before it reaches the model. */
export function normalizeImpact(impact: Partial<Impact> | null | undefined): Impact {
  const i = impact ?? {};
  return {
    offsetX: finite(i.offsetX as number),
    offsetZ: finite(i.offsetZ as number),
    tiltX: finite(i.tiltX as number),
    tiltZ: finite(i.tiltZ as number),
    power: clamp01(finite(i.power as number, 1)),
  };
}

/**
 * Fraction of the can's circular lid that the rectangular sole covers.
 *
 * Sampled on a fixed polar grid rather than solved analytically: it runs once
 * per stomp, it is exact to well under a percent, and it stays readable.
 */
export function lidCoverage(offsetX: number, offsetZ: number): number {
  const RINGS = 24;
  const SPOKES = 48;
  let inside = 0;
  let total = 0;
  for (let r = 0; r < RINGS; r++) {
    // Equal-area ring radii, so every sample carries the same weight.
    const radius = CAN_RADIUS * Math.sqrt((r + 0.5) / RINGS);
    for (let s = 0; s < SPOKES; s++) {
      const a = ((s + 0.5) / SPOKES) * Math.PI * 2;
      // Sample point on the lid, expressed in the sole's frame.
      const px = radius * Math.cos(a) - offsetX;
      const pz = radius * Math.sin(a) - offsetZ;
      total++;
      if (Math.abs(px) <= FOOT_HALF_WIDTH && Math.abs(pz) <= FOOT_HALF_LENGTH) inside++;
    }
  }
  return total === 0 ? 0 : inside / total;
}

/** True when the sole rectangle overlaps the can's lid disc at all. */
export function hasContact(offsetX: number, offsetZ: number): boolean {
  const dx = Math.max(Math.abs(offsetX) - FOOT_HALF_WIDTH, 0);
  const dz = Math.max(Math.abs(offsetZ) - FOOT_HALF_LENGTH, 0);
  return Math.hypot(dx, dz) < CAN_RADIUS;
}

function normalize(x: number, z: number): Vec2 {
  const len = Math.hypot(x, z);
  if (len < 1e-9) return ZERO;
  return { x: x / len, z: z / len };
}

/**
 * Which way the pressure is concentrated, as a unit vector.
 *
 * Two things push the can off its axis: the sole landing to one side of it,
 * and the sole rolling so that one edge arrives first. Both are folded into a
 * single "pressed side"; the can then escapes the other way.
 */
export function pressDirection(impact: Impact): Vec2 {
  const radial = Math.hypot(impact.offsetX, impact.offsetZ);
  const tiltMag = Math.hypot(impact.tiltX, impact.tiltZ);
  const offsetUnit = normalize(impact.offsetX, impact.offsetZ);
  // Rolling by +tiltZ dips the -X edge; pitching by +tiltX dips the +Z edge.
  const edgeUnit = normalize(-impact.tiltZ, impact.tiltX);
  const wOffset = clamp01(radial / MAX_CONTACT_RADIUS);
  const wTilt = clamp01(tiltMag / MAX_TILT) * 0.8;
  return normalize(offsetUnit.x * wOffset + edgeUnit.x * wTilt, offsetUnit.z * wOffset + edgeUnit.z * wTilt);
}

/** The pristine can, for misses and for the initial render state. */
export function pristineOutcome(): CrushOutcome {
  return {
    contact: false,
    coverage: 0,
    heightRatio: 1,
    asymmetry: 0,
    foldAngle: 0,
    tipAngle: 0,
    escapeDir: ZERO,
    launch: 0,
    bulge: 0,
    buckleHeight: 0.5,
    offsetDistance: 0,
    tiltMagnitude: 0,
    offsetError: 0,
    tiltError: 0,
    power: 0,
  };
}

/**
 * The deformation model. Deterministic: the same impact always produces the
 * same can.
 */
export function crushCan(rawImpact: Partial<Impact> | null | undefined): CrushOutcome {
  const impact = normalizeImpact(rawImpact);
  const offsetDistance = Math.hypot(impact.offsetX, impact.offsetZ);
  const tiltMagnitude = Math.hypot(impact.tiltX, impact.tiltZ);

  if (!hasContact(impact.offsetX, impact.offsetZ)) {
    // A clean miss leaves the can exactly as it was.
    return {
      ...pristineOutcome(),
      offsetDistance,
      tiltMagnitude,
      offsetError: deadZone(offsetDistance, CENTER_DEAD_ZONE),
      tiltError: deadZone(tiltMagnitude, TILT_DEAD_ZONE),
      power: impact.power,
    };
  }

  // Errors inside the dead zones are treated as no error at all, here as well
  // as in the score, so that what the player sees and what they are marked on
  // agree right up to a flawless stomp.
  const offsetError = deadZone(offsetDistance, CENTER_DEAD_ZONE);
  const tiltError = deadZone(tiltMagnitude, TILT_DEAD_ZONE);

  const coverage = lidCoverage(impact.offsetX, impact.offsetZ);
  const centering = Math.exp(-Math.pow(offsetError / CENTER_SIGMA, 2));
  const uprightness = clamp01(1 - tiltError / MAX_TILT);

  // A stomp launched from near the top of the foot's bob delivers full force;
  // anything above the dead zone counts as full so a 100 stays reachable.
  const effectivePower = impact.power >= POWER_DEAD_ZONE ? 1 : impact.power;

  // How much of the stomp actually goes into flattening the can. A sole that
  // only clips the rim, arrives on edge, or is still rising does less.
  const effectiveness = clamp01(
    coverage * (0.25 + 0.75 * uprightness) * (0.35 + 0.65 * centering) * (0.7 + 0.3 * effectivePower),
  );

  const heightRatio = 1 - (1 - MIN_HEIGHT_RATIO) * effectiveness;

  const asymmetry = clamp01(
    0.75 * (offsetError / MAX_CONTACT_RADIUS) + 0.55 * (tiltError / MAX_TILT),
  );

  const press = pressDirection(impact);
  // `|| 0` keeps a negated zero from leaking out as -0.
  const escapeDir: Vec2 = { x: -press.x || 0, z: -press.z || 0 };

  // Only a badly lopsided hit sends the can skidding out from under the sole.
  const launch = clamp01((asymmetry - 0.5) / 0.5) * impact.power * (1 - coverage * 0.45);

  // A clean crush concertinas and pushes its waist outwards; a folded one does not.
  const bulge = clamp01((1 - asymmetry) * effectiveness);

  // Where along the can the buckle forms: centred hits fold in the middle,
  // edge hits crease near the top where the sole caught them.
  const buckleHeight = 0.5 + 0.28 * asymmetry;

  return {
    contact: true,
    coverage,
    heightRatio,
    asymmetry,
    foldAngle: asymmetry * MAX_FOLD_ANGLE,
    // Only a badly lopsided stomp knocks the can off its base.
    tipAngle: clamp01((asymmetry - 0.3) / 0.7) * MAX_TIP_ANGLE,
    escapeDir,
    launch,
    bulge,
    buckleHeight,
    offsetDistance,
    tiltMagnitude,
    offsetError,
    tiltError,
    power: impact.power,
  };
}
