import { describe, expect, it } from 'vitest';
import {
  labelForScore,
  scoreComponents,
  scoreImpact,
  scoreOutcome,
} from '../src/domain/scoring';
import { crushCan, hasContact, lidCoverage, normalizeImpact } from '../src/domain/crush';
import { CAN_RADIUS, FOOT_HALF_LENGTH, FOOT_HALF_WIDTH } from '../src/domain/constants';
import type { Impact } from '../src/domain/types';

const perfect: Impact = { offsetX: 0, offsetZ: 0, tiltX: 0, tiltZ: 0, power: 1 };

function impact(over: Partial<Impact>): Impact {
  return { ...perfect, ...over };
}

describe('score range and format', () => {
  it('gives a flawless stomp exactly 100', () => {
    expect(scoreImpact(perfect).score).toBe(100);
  });

  it('gives a complete miss exactly 0', () => {
    const wide = scoreImpact(impact({ offsetX: 3 }));
    expect(wide.score).toBe(0);
    expect(wide.label).toBe('Miss');
    expect(wide.outcome.contact).toBe(false);
  });

  it('always returns an integer between 0 and 100', () => {
    for (let x = -2.5; x <= 2.5; x += 0.05) {
      for (let z = -1.8; z <= 1.8; z += 0.3) {
        for (const tilt of [0, 0.08, 0.3, 0.9]) {
          const { score } = scoreImpact(impact({ offsetX: x, offsetZ: z, tiltZ: tilt }));
          expect(Number.isInteger(score)).toBe(true);
          expect(score).toBeGreaterThanOrEqual(0);
          expect(score).toBeLessThanOrEqual(100);
        }
      }
    }
  });

  it('never scores 0 when the sole actually touched the can', () => {
    // Just inside the contact radius, on the worst possible angle.
    const grazing = impact({ offsetX: FOOT_HALF_WIDTH + CAN_RADIUS - 0.005, tiltZ: 1.2 });
    const scored = scoreImpact(grazing);
    expect(scored.outcome.contact).toBe(true);
    expect(scored.score).toBeGreaterThanOrEqual(1);
    expect(scored.score).toBeLessThan(15);
  });

  it('reserves 100 for near-perfect stomps, not merely good ones', () => {
    expect(scoreImpact(impact({ offsetX: 0.08 })).score).toBeLessThan(100);
    expect(scoreImpact(impact({ tiltZ: 0.09 })).score).toBeLessThan(100);
    expect(scoreImpact(impact({ offsetX: 0.05, tiltX: 0.05 })).score).toBeLessThan(100);
    // A good-but-not-great stomp lands in the eighties.
    const good = scoreImpact(impact({ offsetX: 0.11, tiltZ: 0.08 })).score;
    expect(good).toBeGreaterThan(75);
    expect(good).toBeLessThan(92);
    // But a stomp inside the dead zone still counts as flawless.
    expect(scoreImpact(impact({ offsetX: 0.02, tiltZ: 0.02 })).score).toBe(100);
  });

  it('scores an edge strike that folds the can around ten', () => {
    const edge = scoreImpact(impact({ offsetX: 0.62, tiltZ: 0.34 }));
    expect(edge.score).toBeGreaterThan(2);
    expect(edge.score).toBeLessThan(20);
    expect(edge.outcome.asymmetry).toBeGreaterThan(0.6);
  });
});

describe('monotonicity', () => {
  it('scores higher the closer the stomp lands to the axis', () => {
    let previous = Infinity;
    for (let offset = 0; offset <= 0.7; offset += 0.02) {
      const score = scoreImpact(impact({ offsetX: offset })).score;
      expect(score).toBeLessThanOrEqual(previous);
      previous = score;
    }
  });

  it('scores higher the more level the foot is', () => {
    let previous = Infinity;
    for (let tilt = 0; tilt <= 0.6; tilt += 0.02) {
      const score = scoreImpact(impact({ tiltZ: tilt })).score;
      expect(score).toBeLessThanOrEqual(previous);
      previous = score;
    }
  });

  it('scores higher with more power behind the stomp', () => {
    let previous = -Infinity;
    for (let power = 0.5; power <= 1; power += 0.05) {
      const score = scoreImpact(impact({ power })).score;
      expect(score).toBeGreaterThanOrEqual(previous);
      previous = score;
    }
  });

  it('ranks a sequence of increasingly accurate stomps in order', () => {
    const ladder = [
      impact({ offsetX: 0.9, tiltZ: 0.5 }),
      impact({ offsetX: 0.55, tiltZ: 0.35 }),
      impact({ offsetX: 0.3, tiltZ: 0.2 }),
      impact({ offsetX: 0.14, tiltZ: 0.1 }),
      impact({ offsetX: 0.05, tiltZ: 0.04 }),
      perfect,
    ].map((i) => scoreImpact(i).score);
    for (let i = 1; i < ladder.length; i++) {
      expect(ladder[i]!).toBeGreaterThan(ladder[i - 1]!);
    }
  });
});

describe('labels', () => {
  it('bands the score into the five results', () => {
    expect(labelForScore(0, false)).toBe('Miss');
    expect(labelForScore(0, true)).toBe('Miss');
    expect(labelForScore(1, true)).toBe('Glancing Blow');
    expect(labelForScore(29, true)).toBe('Glancing Blow');
    expect(labelForScore(30, true)).toBe('Bent It');
    expect(labelForScore(59, true)).toBe('Bent It');
    expect(labelForScore(60, true)).toBe('Clean Stomp');
    expect(labelForScore(89, true)).toBe('Clean Stomp');
    expect(labelForScore(90, true)).toBe('Perfect Crush');
    expect(labelForScore(100, true)).toBe('Perfect Crush');
  });

  it('never calls a hit a miss just because it scored badly', () => {
    const grazing = scoreImpact(impact({ offsetX: 0.7, tiltZ: 1.4 }));
    expect(grazing.outcome.contact).toBe(true);
    expect(grazing.label).not.toBe('Miss');
  });
});

describe('explanations', () => {
  it('names the side the foot drifted to', () => {
    expect(scoreImpact(impact({ offsetX: 0.4 })).explanation).toContain('right');
    expect(scoreImpact(impact({ offsetX: -0.4 })).explanation).toContain('left');
    expect(scoreImpact(impact({ offsetZ: 0.4 })).explanation).toContain('far side');
    expect(scoreImpact(impact({ offsetZ: -0.4 })).explanation).toContain('near side');
  });

  it('calls out a centred but angled stomp', () => {
    expect(scoreImpact(impact({ tiltZ: 0.25 })).explanation).toBe(
      'Centred, but the foot came down angled.',
    );
  });

  it('praises a flawless stomp', () => {
    expect(scoreImpact(perfect).explanation).toBe('Dead centre and flat as a coin.');
  });

  it('explains a miss', () => {
    expect(scoreImpact(impact({ offsetX: 4 })).explanation).toMatch(/came down/);
  });
});

describe('bad input', () => {
  it('treats NaN and undefined as a dead-centre stomp rather than crashing', () => {
    expect(scoreImpact(null).score).toBe(100);
    expect(scoreImpact({}).score).toBe(100);
    expect(scoreImpact({ offsetX: NaN, offsetZ: NaN, tiltX: NaN, tiltZ: NaN, power: NaN }).score)
      .toBeGreaterThanOrEqual(0);
  });

  it('clamps power to 0..1', () => {
    expect(normalizeImpact({ power: 12 }).power).toBe(1);
    expect(normalizeImpact({ power: -4 }).power).toBe(0);
    // A missing or non-finite power reads as an ordinary full-strength stomp.
    expect(normalizeImpact({ power: Number.POSITIVE_INFINITY }).power).toBe(1);
    expect(normalizeImpact({}).power).toBe(1);
  });

  it('survives absurd offsets', () => {
    expect(scoreImpact(impact({ offsetX: 1e9, offsetZ: -1e9 })).score).toBe(0);
  });
});

describe('components', () => {
  it('reports all four sub-scores at full for a flawless stomp', () => {
    const c = scoreComponents(crushCan(perfect));
    expect(c.centering).toBeCloseTo(1, 5);
    expect(c.uprightness).toBeCloseTo(1, 5);
    expect(c.flatness).toBeCloseTo(1, 5);
    expect(c.symmetry).toBeCloseTo(1, 5);
  });

  it('zeroes every component on a miss', () => {
    const missed = normalizeImpact({ offsetX: 5 });
    const breakdown = scoreOutcome(missed, crushCan(missed));
    expect(breakdown.components).toEqual({
      centering: 0,
      uprightness: 0,
      flatness: 0,
      symmetry: 0,
    });
  });
});

describe('contact geometry', () => {
  it('covers the whole lid when the sole is centred', () => {
    expect(lidCoverage(0, 0)).toBeCloseTo(1, 6);
  });

  it('covers about half the lid when the sole edge splits it', () => {
    expect(lidCoverage(FOOT_HALF_WIDTH, 0)).toBeGreaterThan(0.4);
    expect(lidCoverage(FOOT_HALF_WIDTH, 0)).toBeLessThan(0.6);
  });

  it('covers nothing once the sole has cleared the can', () => {
    expect(lidCoverage(FOOT_HALF_WIDTH + CAN_RADIUS + 0.01, 0)).toBe(0);
    expect(hasContact(FOOT_HALF_WIDTH + CAN_RADIUS + 0.01, 0)).toBe(false);
    expect(hasContact(0, FOOT_HALF_LENGTH + CAN_RADIUS + 0.01)).toBe(false);
  });

  it('still counts a corner clip as contact', () => {
    expect(hasContact(FOOT_HALF_WIDTH + 0.1, FOOT_HALF_LENGTH + 0.1)).toBe(true);
  });
});
