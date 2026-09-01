/**
 * The game's state machine.
 *
 * Pure data plus pure transitions: no DOM, no three.js, no timers. The render
 * layer drives it with `tick` and reads the result out, which is what lets the
 * whole round loop be tested without a browser.
 */

import { CAN_JITTER_X, CAN_JITTER_Z } from './constants';
import { crushCan, pristineOutcome } from './crush';
import { clamp, finite, seededUnit } from './math';
import { scoreOutcome } from './scoring';
import type { Aim } from './input';
import { clampAim } from './input';
import type { CrushOutcome, Impact, ScoreBreakdown } from './types';
import { wobbleAt } from './wobble';

export type Phase = 'intro' | 'aiming' | 'stomping' | 'result';

export interface GameState {
  phase: Phase;
  /** 1-based round counter. */
  round: number;
  /** Seed for this round's wobble phase and can placement. */
  seed: number;
  /** Seconds elapsed in this round; drives the wobble. */
  clock: number;
  canX: number;
  canZ: number;
  aim: Aim;
  /** Frozen impact for the stomp in flight, or null. */
  impact: Impact | null;
  outcome: CrushOutcome;
  result: ScoreBreakdown | null;
  best: number;
  /** Rounds completed this session. */
  attempts: number;
  /** False until the player has completed their first stomp. */
  tutorialDone: boolean;
  paused: boolean;
  muted: boolean;
  reducedMotion: boolean;
}

function canPlacement(seed: number): { canX: number; canZ: number } {
  return {
    canX: (seededUnit(seed, 1) * 2 - 1) * CAN_JITTER_X,
    canZ: (seededUnit(seed, 2) * 2 - 1) * CAN_JITTER_Z,
  };
}

/** A fresh game. `seed` makes the whole session reproducible in tests. */
export function createGame(seed = 1, options: Partial<Pick<GameState, 'muted' | 'reducedMotion' | 'best' | 'tutorialDone'>> = {}): GameState {
  const placement = canPlacement(seed);
  return {
    phase: 'intro',
    round: 1,
    seed,
    clock: 0,
    ...placement,
    aim: { x: placement.canX, z: placement.canZ },
    impact: null,
    outcome: pristineOutcome(),
    result: null,
    best: clamp(finite(options.best ?? 0), 0, 100),
    attempts: 0,
    tutorialDone: options.tutorialDone ?? false,
    paused: false,
    muted: options.muted ?? false,
    reducedMotion: options.reducedMotion ?? false,
  };
}

/** True while the player may move the foot and trigger a stomp. */
export function isLive(state: GameState): boolean {
  return !state.paused && (state.phase === 'aiming' || state.phase === 'intro');
}

/** Advances the wobble clock. Frozen while paused, stomping or showing a result. */
export function tick(state: GameState, dt: number): GameState {
  if (!isLive(state)) return state;
  const step = clamp(finite(dt), 0, 0.1);
  if (step === 0) return state;
  return { ...state, clock: state.clock + step };
}

export function setAim(state: GameState, aim: Aim): GameState {
  if (!isLive(state)) return state;
  return { ...state, aim: clampAim(aim) };
}

/** Where the sole centre is right now, in world coordinates. */
export function solePosition(state: GameState): { x: number; z: number; hover: number } {
  const w = wobbleAt(state.clock, state.seed);
  return { x: state.aim.x + w.driftX, z: state.aim.z + w.driftZ, hover: w.hover };
}

/** The impact the game would record if the player stomped this instant. */
export function impactNow(state: GameState): Impact {
  const w = wobbleAt(state.clock, state.seed);
  return {
    offsetX: state.aim.x + w.driftX - state.canX,
    offsetZ: state.aim.z + w.driftZ - state.canZ,
    tiltX: w.tiltX,
    tiltZ: w.tiltZ,
    power: w.power,
  };
}

/**
 * Commits the stomp. The impact is frozen here, at the moment the player
 * pressed, so the animation that follows is a replay of a decision already
 * made rather than something that can drift.
 */
export function stomp(state: GameState): GameState {
  if (!isLive(state)) return state;
  const impact = impactNow(state);
  const outcome = crushCan(impact);
  const result = scoreOutcome(impact, outcome);
  return {
    ...state,
    phase: 'stomping',
    impact,
    outcome,
    result,
    tutorialDone: true,
  };
}

/** Called when the impact animation finishes; banks the score. */
export function revealResult(state: GameState): GameState {
  if (state.phase !== 'stomping' || !state.result) return state;
  return {
    ...state,
    phase: 'result',
    attempts: state.attempts + 1,
    best: Math.max(state.best, state.result.score),
  };
}

/**
 * Starts the next round. Everything round-scoped is rebuilt from scratch;
 * only the session totals and the player's preferences survive.
 */
export function nextRound(state: GameState): GameState {
  const seed = (Math.imul(state.seed, 1103515245) + state.round * 12345) >>> 0;
  const placement = canPlacement(seed);
  return {
    ...state,
    phase: 'aiming',
    round: state.round + 1,
    seed,
    clock: 0,
    ...placement,
    aim: { x: placement.canX, z: placement.canZ },
    impact: null,
    outcome: pristineOutcome(),
    result: null,
    paused: false,
  };
}

/** Leaves the tutorial overlay for the live game without losing the round. */
export function beginPlay(state: GameState): GameState {
  return state.phase === 'intro' ? { ...state, phase: 'aiming' } : state;
}

export function setPaused(state: GameState, paused: boolean): GameState {
  if (state.phase === 'stomping') return state;
  return { ...state, paused };
}

export function setMuted(state: GameState, muted: boolean): GameState {
  return { ...state, muted };
}

export function setReducedMotion(state: GameState, reducedMotion: boolean): GameState {
  return { ...state, reducedMotion };
}
