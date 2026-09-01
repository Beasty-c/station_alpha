/**
 * Scores a stomp out of 100.
 *
 * The score is built from four things the player can see: how close to the
 * axis the sole landed, how level it was, how flat the can ended up, and how
 * even the crush is. The last two come straight out of the deformation model,
 * so the number always matches the wreckage on screen.
 */

import { CENTER_SIGMA, MAX_TILT, MIN_HEIGHT_RATIO, POWER_DEAD_ZONE } from './constants';
import { crushCan, normalizeImpact } from './crush';
import { clamp01 } from './math';
import type { CrushOutcome, Impact, ResultLabel, ScoreBreakdown } from './types';

const WEIGHTS = {
  centering: 0.3,
  uprightness: 0.18,
  flatness: 0.32,
  symmetry: 0.2,
} as const;

/** Pulls the top of the range in slightly so a merely good hit is not a 100. */
const SHARPNESS = 1.12;

/** Lid coverage at which the stomp counts as a solid, full-value contact. */
const SOLID_CONTACT_COVERAGE = 0.55;

export interface ScoreComponents {
  centering: number;
  uprightness: number;
  flatness: number;
  symmetry: number;
}

/** The four sub-scores, each 0 to 1, derived from an outcome. */
export function scoreComponents(outcome: CrushOutcome): ScoreComponents {
  return {
    centering: Math.exp(-Math.pow(outcome.offsetError / CENTER_SIGMA, 2)),
    uprightness: clamp01(1 - outcome.tiltError / MAX_TILT),
    flatness: clamp01((1 - outcome.heightRatio) / (1 - MIN_HEIGHT_RATIO)),
    symmetry: clamp01(1 - outcome.asymmetry),
  };
}

/**
 * The score band. `Miss` is reserved for a stomp that never touched the can.
 */
export function labelForScore(score: number, contact: boolean): ResultLabel {
  if (!contact || score <= 0) return 'Miss';
  if (score >= 90) return 'Perfect Crush';
  if (score >= 60) return 'Clean Stomp';
  if (score >= 30) return 'Bent It';
  return 'Glancing Blow';
}

/** A short, specific sentence about the biggest thing that went wrong. */
export function explainImpact(rawImpact: Partial<Impact>, outcome: CrushOutcome): string {
  const impact = normalizeImpact(rawImpact);
  const sideways = Math.abs(impact.offsetX) >= Math.abs(impact.offsetZ);
  const direction = sideways
    ? impact.offsetX > 0
      ? 'right'
      : 'left'
    : impact.offsetZ > 0
      ? 'far side'
      : 'near side';

  if (!outcome.contact) {
    return sideways
      ? `The foot came down well to the ${direction} of the can.`
      : `The foot came down past the ${direction} of the can.`;
  }

  const offsetError = outcome.offsetError / CENTER_SIGMA;
  const tiltError = outcome.tiltError / MAX_TILT;

  if (offsetError < 0.12 && tiltError < 0.12) {
    return outcome.power < POWER_DEAD_ZONE - 0.06
      ? 'Dead centre, but the foot was still on its way up.'
      : 'Dead centre and flat as a coin.';
  }
  if (offsetError >= tiltError * 1.3) {
    if (offsetError > 1.6) return `Way off to the ${direction}.`;
    return offsetError > 0.7 ? `Off to the ${direction}.` : `A shade to the ${direction}.`;
  }
  if (tiltError > offsetError * 1.3) {
    return offsetError < 0.25
      ? 'Centred, but the foot came down angled.'
      : 'Caught it on the edge of the sole.';
  }
  return `Angled, and a little to the ${direction}.`;
}

/** Scores an outcome that has already been computed. */
export function scoreOutcome(impact: Impact, outcome: CrushOutcome): ScoreBreakdown {
  if (!outcome.contact) {
    return {
      score: 0,
      label: 'Miss',
      explanation: explainImpact(impact, outcome),
      components: { centering: 0, uprightness: 0, flatness: 0, symmetry: 0 },
    };
  }

  const components = scoreComponents(outcome);
  const raw = clamp01(
    WEIGHTS.centering * components.centering +
      WEIGHTS.uprightness * components.uprightness +
      WEIGHTS.flatness * components.flatness +
      WEIGHTS.symmetry * components.symmetry,
  );

  // A sole that only clips the rim cannot bank full marks for being level: the
  // form scores are worth what the contact was worth.
  const connection = 0.35 + 0.65 * clamp01(outcome.coverage / SOLID_CONTACT_COVERAGE);

  // Touching the can is always worth at least a point, so 0 means "missed".
  const score = Math.max(
    1,
    Math.min(100, Math.round(Math.pow(raw, SHARPNESS) * connection * 100)),
  );

  return {
    score,
    label: labelForScore(score, true),
    explanation: explainImpact(impact, outcome),
    components,
  };
}

/** Convenience: crush and score in one step. */
export function scoreImpact(impact: Partial<Impact> | null | undefined): ScoreBreakdown & {
  outcome: CrushOutcome;
} {
  const normalized = normalizeImpact(impact);
  const outcome = crushCan(normalized);
  return { ...scoreOutcome(normalized, outcome), outcome };
}
