import { describe, expect, it } from 'vitest';
import {
  HOVER_BASE,
  HOVER_BOB,
  WOBBLE_PERIOD,
  nextPerfectInstant,
  phaseForSeed,
  tiltMagnitudeAt,
  windowCloseness,
  wobbleAt,
} from '../src/domain/wobble';
import { crushCan } from '../src/domain/crush';
import { scoreOutcome } from '../src/domain/scoring';

const SEEDS = [0, 1, 2, 7, 42, 1337, 987654321, -5];

describe('wobble', () => {
  it('repeats exactly once per period', () => {
    for (const seed of SEEDS) {
      for (const t of [0, 0.37, 1.1, 2.05]) {
        const a = wobbleAt(t, seed);
        const b = wobbleAt(t + WOBBLE_PERIOD, seed);
        expect(b.driftX).toBeCloseTo(a.driftX, 10);
        expect(b.driftZ).toBeCloseTo(a.driftZ, 10);
        expect(b.tiltX).toBeCloseTo(a.tiltX, 10);
        expect(b.tiltZ).toBeCloseTo(a.tiltZ, 10);
        expect(b.hover).toBeCloseTo(a.hover, 10);
      }
    }
  });

  it('stays inside its advertised envelope', () => {
    for (const seed of SEEDS) {
      for (let t = 0; t < WOBBLE_PERIOD * 2; t += 0.01) {
        const w = wobbleAt(t, seed);
        expect(Math.abs(w.driftX)).toBeLessThanOrEqual(0.27);
        expect(Math.abs(w.driftZ)).toBeLessThanOrEqual(0.2);
        expect(Math.abs(w.tiltX)).toBeLessThanOrEqual(0.111);
        expect(Math.abs(w.tiltZ)).toBeLessThanOrEqual(0.221);
        expect(w.hover).toBeGreaterThanOrEqual(HOVER_BASE - HOVER_BOB - 1e-9);
        expect(w.hover).toBeLessThanOrEqual(HOVER_BASE + HOVER_BOB + 1e-9);
        expect(w.power).toBeGreaterThan(0.8);
        expect(w.power).toBeLessThanOrEqual(1);
      }
    }
  });

  it('offers a perfectly level, full-power instant twice per cycle, for every seed', () => {
    for (const seed of SEEDS) {
      let t = 0;
      for (let i = 0; i < 4; i++) {
        const perfectAt = nextPerfectInstant(t, seed);
        expect(perfectAt).toBeGreaterThan(t - 1e-9);
        const w = wobbleAt(perfectAt, seed);
        expect(Math.hypot(w.tiltX, w.tiltZ)).toBeLessThan(1e-9);
        expect(w.power).toBeCloseTo(1, 9);
        t = perfectAt + 1e-6;
      }
      // Two per 2.4 s cycle means one every 1.2 s.
      const first = nextPerfectInstant(0, seed);
      const second = nextPerfectInstant(first + 1e-6, seed);
      expect(second - first).toBeCloseTo(WOBBLE_PERIOD / 2, 6);
    }
  });

  it('lets a player who cancels the drift at that instant score 100', () => {
    for (const seed of SEEDS) {
      const t = nextPerfectInstant(0.01, seed);
      const w = wobbleAt(t, seed);
      // The player has parked the aim so the drift cancels exactly.
      const impact = {
        offsetX: 0,
        offsetZ: 0,
        tiltX: w.tiltX,
        tiltZ: w.tiltZ,
        power: w.power,
      };
      expect(scoreOutcome(impact, crushCan(impact)).score).toBe(100);
    }
  });

  it('varies the phase between seeds without varying the difficulty', () => {
    const phases = SEEDS.map(phaseForSeed);
    expect(new Set(phases.map((p) => p.toFixed(4))).size).toBeGreaterThan(SEEDS.length - 2);
    for (const p of phases) {
      expect(p).toBeGreaterThanOrEqual(0);
      expect(p).toBeLessThan(Math.PI * 2);
    }
  });

  it('reports how close the foot is to its level window', () => {
    const seed = 9;
    const t = nextPerfectInstant(0, seed);
    expect(windowCloseness(t, seed)).toBeCloseTo(1, 6);
    expect(windowCloseness(t + WOBBLE_PERIOD / 4, seed)).toBeLessThan(0.2);
    expect(tiltMagnitudeAt(t + WOBBLE_PERIOD / 4, seed)).toBeGreaterThan(0.05);
  });

  it('treats a non-finite clock as time zero rather than producing NaN', () => {
    const w = wobbleAt(Number.NaN, 3);
    expect(Number.isFinite(w.driftX)).toBe(true);
    expect(Number.isFinite(w.tiltZ)).toBe(true);
    expect(Number.isFinite(w.hover)).toBe(true);
  });
});
