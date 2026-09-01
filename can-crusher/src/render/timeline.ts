/**
 * The stomp animation timeline.
 *
 * Pure: given how long ago the player pressed, it says where the foot is, how
 * far the crush has played, and whether the result is ready to show. The
 * outcome it animates was decided at the moment of the press.
 */

import { CAN_HEIGHT } from '../domain/constants';
import { clamp01, easeInQuad, easeOutCubic, lerp, smoothstep } from '../domain/math';
import type { CrushOutcome } from '../domain/types';

export const PHASES = {
  /** Wind-up: the foot rises and stretches. */
  anticipate: 0.16,
  /** The slam. */
  drop: 0.12,
  /** The can gives way. */
  crush: 0.24,
  /** A beat on the wreckage before the score appears. */
  settle: 0.3,
  /** The foot withdraws, ready for the next round. */
  lift: 0.34,
} as const;

export const STOMP_DURATION =
  PHASES.anticipate + PHASES.drop + PHASES.crush + PHASES.settle + PHASES.lift;

/** The score card appears once the can has settled, not when the foot leaves. */
export const REVEAL_AT = PHASES.anticipate + PHASES.drop + PHASES.crush + PHASES.settle;

export const IMPACT_AT = PHASES.anticipate + PHASES.drop;

const LIFT_HEIGHT = 0.46;

export interface StompFrame {
  /** Height of the sole above the slab. */
  footY: number;
  /** Vertical scale of the foot, for squash and stretch. */
  squash: number;
  /** How far the can deformation has played, 0 to 1. */
  crush: number;
  /** True on the frame the sole meets the can. */
  impact: boolean;
  /** True once the score card should be on screen. */
  reveal: boolean;
  /** True when the whole sequence has finished. */
  done: boolean;
}

/**
 * @param elapsed seconds since the player pressed
 * @param previousElapsed the same value on the previous frame, so the impact
 *        can be reported exactly once
 * @param hoverY the height the foot was resting at when the player pressed
 */
export function stompFrame(
  elapsed: number,
  previousElapsed: number,
  hoverY: number,
  outcome: CrushOutcome,
): StompFrame {
  const t = Math.max(0, elapsed);
  const restY = CAN_HEIGHT + hoverY;
  // A miss carries the foot all the way to the slab beside the can.
  const contactY = outcome.contact ? CAN_HEIGHT : 0;

  const impact = previousElapsed < IMPACT_AT && t >= IMPACT_AT;
  const reveal = t >= REVEAL_AT;
  const done = t >= STOMP_DURATION;

  if (t < PHASES.anticipate) {
    const p = smoothstep(t / PHASES.anticipate);
    return {
      footY: lerp(restY, restY + LIFT_HEIGHT, p),
      squash: lerp(1, 1.14, p),
      crush: 0,
      impact,
      reveal,
      done,
    };
  }

  const afterAnticipate = t - PHASES.anticipate;
  if (afterAnticipate < PHASES.drop) {
    const p = easeInQuad(afterAnticipate / PHASES.drop);
    return {
      footY: lerp(restY + LIFT_HEIGHT, contactY, p),
      squash: lerp(1.14, 0.94, p),
      crush: 0,
      impact,
      reveal,
      done,
    };
  }

  const afterDrop = afterAnticipate - PHASES.drop;
  if (afterDrop < PHASES.crush) {
    const p = easeOutCubic(afterDrop / PHASES.crush);
    const canTop = CAN_HEIGHT * lerp(1, outcome.heightRatio, p);
    return {
      footY: outcome.contact ? canTop : 0,
      // A hard landing squashes the boot, then it recovers.
      squash: lerp(0.86, 1, easeOutCubic(p)),
      crush: p,
      impact,
      reveal,
      done,
    };
  }

  const restingY = outcome.contact ? CAN_HEIGHT * outcome.heightRatio : 0;
  const afterCrush = afterDrop - PHASES.crush;
  if (afterCrush < PHASES.settle) {
    return { footY: restingY, squash: 1, crush: 1, impact, reveal, done };
  }

  const p = smoothstep(clamp01((afterCrush - PHASES.settle) / PHASES.lift));
  return {
    footY: lerp(restingY, restY, p),
    squash: 1,
    crush: 1,
    impact,
    reveal,
    done,
  };
}
