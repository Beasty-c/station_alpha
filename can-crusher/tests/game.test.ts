import { describe, expect, it } from 'vitest';
import {
  beginPlay,
  createGame,
  impactNow,
  isLive,
  nextRound,
  revealResult,
  setAim,
  setMuted,
  setPaused,
  setReducedMotion,
  solePosition,
  stomp,
  tick,
} from '../src/domain/game';
import { CAN_JITTER_X, CAN_JITTER_Z } from '../src/domain/constants';
import { nextPerfectInstant, wobbleAt } from '../src/domain/wobble';

/**
 * `tick` deliberately caps a single frame, so tests wind the clock forward the
 * way the render loop does: in frame-sized steps.
 */
function advance(state: ReturnType<typeof createGame>, seconds: number) {
  const STEP = 1 / 120;
  let next = state;
  let remaining = seconds;
  while (remaining > 1e-12) {
    const step = Math.min(STEP, remaining);
    next = tick(next, step);
    remaining -= step;
  }
  return next;
}

function playRound(seedGame = createGame(11), aim = { x: 0, z: 0 }) {
  let state = beginPlay(seedGame);
  state = setAim(state, aim);
  state = stomp(state);
  return revealResult(state);
}

describe('round lifecycle', () => {
  it('starts on the tutorial with a pristine can and no result', () => {
    const state = createGame(3);
    expect(state.phase).toBe('intro');
    expect(state.result).toBeNull();
    expect(state.outcome.contact).toBe(false);
    expect(state.outcome.heightRatio).toBe(1);
    expect(state.round).toBe(1);
    expect(state.attempts).toBe(0);
    expect(state.tutorialDone).toBe(false);
  });

  it('runs aim, stomp and reveal in order', () => {
    let state = beginPlay(createGame(5));
    expect(state.phase).toBe('aiming');
    state = advance(state, 0.4);
    expect(state.clock).toBeCloseTo(0.4, 9);

    state = stomp(state);
    expect(state.phase).toBe('stomping');
    expect(state.impact).not.toBeNull();
    expect(state.result).not.toBeNull();
    expect(state.attempts).toBe(0);

    state = revealResult(state);
    expect(state.phase).toBe('result');
    expect(state.attempts).toBe(1);
  });

  it('freezes the wobble clock once the stomp is committed', () => {
    let state = stomp(beginPlay(createGame(5)));
    const frozen = state.clock;
    state = advance(state, 1);
    expect(state.clock).toBe(frozen);
  });

  it('ignores a second stomp during the animation and the result screen', () => {
    const stomping = stomp(beginPlay(createGame(5)));
    expect(stomp(stomping)).toBe(stomping);
    const result = revealResult(stomping);
    expect(stomp(result)).toBe(result);
    expect(revealResult(result)).toBe(result);
  });

  it('marks the tutorial done after the first stomp and never shows it again', () => {
    const state = playRound();
    expect(state.tutorialDone).toBe(true);
    expect(nextRound(state).tutorialDone).toBe(true);
    expect(nextRound(state).phase).toBe('aiming');
  });
});

describe('retry resets the round', () => {
  it('clears the can, the aim, the clock, the impact and the result', () => {
    let state = playRound(createGame(21), { x: 2.2, z: -1.4 });
    expect(state.result).not.toBeNull();

    const fresh = nextRound(state);
    expect(fresh.phase).toBe('aiming');
    expect(fresh.clock).toBe(0);
    expect(fresh.impact).toBeNull();
    expect(fresh.result).toBeNull();
    expect(fresh.outcome.contact).toBe(false);
    expect(fresh.outcome.heightRatio).toBe(1);
    expect(fresh.outcome.foldAngle).toBe(0);
    expect(fresh.outcome.launch).toBe(0);
    expect(fresh.paused).toBe(false);
    expect(fresh.aim).toEqual({ x: fresh.canX, z: fresh.canZ });
    expect(fresh.round).toBe(state.round + 1);
  });

  it('keeps the session totals and the player preferences', () => {
    let state = setMuted(setReducedMotion(playRound(), true), true);
    const best = state.best;
    const attempts = state.attempts;
    state = nextRound(state);
    expect(state.best).toBe(best);
    expect(state.attempts).toBe(attempts);
    expect(state.muted).toBe(true);
    expect(state.reducedMotion).toBe(true);
  });

  it('moves the can a little, and always somewhere reachable', () => {
    let state = createGame(1);
    const seen = new Set<string>();
    for (let i = 0; i < 40; i++) {
      state = revealResult(stomp(beginPlay(state)));
      state = nextRound(state);
      expect(Math.abs(state.canX)).toBeLessThanOrEqual(CAN_JITTER_X);
      expect(Math.abs(state.canZ)).toBeLessThanOrEqual(CAN_JITTER_Z);
      seen.add(`${state.canX.toFixed(3)},${state.canZ.toFixed(3)}`);
    }
    expect(seen.size).toBeGreaterThan(20);
  });
});

describe('best score', () => {
  it('keeps the highest score of the session', () => {
    let state = createGame(4);
    const scores: number[] = [];
    for (let i = 0; i < 6; i++) {
      state = beginPlay(state);
      state = advance(state, 0.21 * (i + 1));
      state = revealResult(stomp(state));
      scores.push(state.result!.score);
      expect(state.best).toBe(Math.max(...scores));
      state = nextRound(state);
    }
  });

  it('starts from a restored session best', () => {
    expect(createGame(1, { best: 73 }).best).toBe(73);
    expect(createGame(1, { best: 900 }).best).toBe(100);
    expect(createGame(1, { best: NaN }).best).toBe(0);
  });
});

describe('pause and mute', () => {
  it('stops the clock while paused and resumes it after', () => {
    let state = setPaused(beginPlay(createGame(2)), true);
    expect(isLive(state)).toBe(false);
    state = advance(state, 1);
    expect(state.clock).toBe(0);
    state = setPaused(state, false);
    state = advance(state, 0.5);
    expect(state.clock).toBeCloseTo(0.5, 9);
  });

  it('refuses to pause mid-stomp so the animation cannot be frozen', () => {
    const stomping = stomp(beginPlay(createGame(2)));
    expect(setPaused(stomping, true)).toBe(stomping);
  });

  it('ignores aim input while paused', () => {
    const paused = setPaused(beginPlay(createGame(2)), true);
    expect(setAim(paused, { x: 2, z: 1 })).toBe(paused);
  });

  it('lets mute be toggled at any time', () => {
    expect(setMuted(createGame(1), true).muted).toBe(true);
    expect(setMuted(stomp(beginPlay(createGame(1))), true).muted).toBe(true);
  });
});

describe('impact capture', () => {
  it('is the aim plus the wobble drift, relative to the can', () => {
    let state = beginPlay(createGame(8));
    state = advance(state, 0.7);
    state = setAim(state, { x: 0.4, z: -0.2 });
    const w = wobbleAt(state.clock, state.seed);
    const impact = impactNow(state);
    expect(impact.offsetX).toBeCloseTo(0.4 + w.driftX - state.canX, 9);
    expect(impact.offsetZ).toBeCloseTo(-0.2 + w.driftZ - state.canZ, 9);
    expect(impact.tiltX).toBeCloseTo(w.tiltX, 9);
    expect(impact.power).toBeCloseTo(w.power, 9);
    const sole = solePosition(state);
    expect(sole.x).toBeCloseTo(0.4 + w.driftX, 9);
  });

  it('scores 100 for a player who cancels the drift on the level beat', () => {
    let state = beginPlay(createGame(6));
    const t = nextPerfectInstant(0.05, state.seed);
    state = advance(state, t);
    const w = wobbleAt(state.clock, state.seed);
    state = setAim(state, { x: state.canX - w.driftX, z: state.canZ - w.driftZ });
    state = revealResult(stomp(state));
    expect(state.result!.score).toBe(100);
    expect(state.result!.label).toBe('Perfect Crush');
    expect(state.best).toBe(100);
  });

  it('scores 0 and leaves the can standing when the foot lands well clear', () => {
    let state = beginPlay(createGame(6));
    state = setAim(state, { x: state.canX + 2.4, z: state.canZ });
    state = revealResult(stomp(state));
    expect(state.result!.score).toBe(0);
    expect(state.result!.label).toBe('Miss');
    expect(state.outcome.contact).toBe(false);
    expect(state.outcome.heightRatio).toBe(1);
  });
});
