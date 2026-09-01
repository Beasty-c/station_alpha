import { describe, expect, it } from 'vitest';
import {
  canBaseRadius,
  canDisplacement,
  crushAmount,
  crushedHeight,
  deformCanPoint,
} from '../src/domain/canShape';
import { crushCan, pristineOutcome } from '../src/domain/crush';
import { CAN_HEIGHT, CAN_RADIUS, MIN_HEIGHT_RATIO } from '../src/domain/constants';

const RINGS = 16;
const STACKS = 12;

function sample(outcome: ReturnType<typeof crushCan>, progress: number) {
  const points = [];
  for (let j = 0; j <= STACKS; j++) {
    for (let i = 0; i < RINGS; i++) {
      points.push(deformCanPoint((i / RINGS) * Math.PI * 2, j / STACKS, outcome, progress));
    }
  }
  return points;
}

const perfect = crushCan({ offsetX: 0, offsetZ: 0, tiltX: 0, tiltZ: 0, power: 1 });
const glancing = crushCan({ offsetX: 0.55, offsetZ: 0, tiltZ: 0.3, power: 1 });
const missed = crushCan({ offsetX: 3, power: 1 });

describe('pristine silhouette', () => {
  it('is widest at the body and narrower at the rim and the base', () => {
    expect(canBaseRadius(0.5)).toBeCloseTo(CAN_RADIUS, 9);
    expect(canBaseRadius(0)).toBeLessThan(CAN_RADIUS);
    expect(canBaseRadius(1)).toBeLessThan(CAN_RADIUS);
    for (let v = 0; v <= 1; v += 0.01) {
      expect(canBaseRadius(v)).toBeLessThanOrEqual(CAN_RADIUS + 1e-9);
      expect(canBaseRadius(v)).toBeGreaterThan(0);
    }
  });

  it('is unchanged at the start of any animation', () => {
    for (const outcome of [perfect, glancing, missed, pristineOutcome()]) {
      const points = sample(outcome, 0);
      const top = Math.max(...points.map((p) => p.y));
      expect(top).toBeCloseTo(CAN_HEIGHT, 6);
      const base = Math.min(...points.map((p) => p.y));
      expect(base).toBeCloseTo(0, 9);
      for (const p of points) expect(Math.hypot(p.x, p.z)).toBeLessThanOrEqual(CAN_RADIUS + 1e-9);
    }
  });
});

describe('a flawless stomp', () => {
  it('flattens the can to the model minimum', () => {
    expect(crushedHeight(perfect, 1)).toBeCloseTo(CAN_HEIGHT * MIN_HEIGHT_RATIO, 6);
    expect(crushAmount(perfect, 1)).toBeCloseTo(1, 6);
    const top = Math.max(...sample(perfect, 1).map((p) => p.y));
    expect(top).toBeCloseTo(CAN_HEIGHT * MIN_HEIGHT_RATIO, 6);
  });

  it('leaves it standing where it was, symmetrical and bulged', () => {
    expect(perfect.foldAngle).toBe(0);
    expect(perfect.tipAngle).toBe(0);
    expect(perfect.launch).toBe(0);
    expect(canDisplacement(perfect, 1)).toEqual({ x: 0, y: 0, z: 0 });
    expect(perfect.bulge).toBeGreaterThan(0.9);

    // Opposite sides of every ring must mirror each other.
    for (let j = 0; j <= STACKS; j++) {
      const v = j / STACKS;
      for (let i = 0; i < RINGS; i++) {
        const theta = (i / RINGS) * Math.PI * 2;
        const a = deformCanPoint(theta, v, perfect, 1);
        const b = deformCanPoint(theta + Math.PI, v, perfect, 1);
        expect(Math.hypot(a.x, a.z)).toBeCloseTo(Math.hypot(b.x, b.z), 9);
        expect(a.y).toBeCloseTo(b.y, 9);
      }
    }
  });

  it('widens the waist beyond the original radius', () => {
    const waist = deformCanPoint(0, 0.5, perfect, 1);
    expect(Math.hypot(waist.x, waist.z)).toBeGreaterThan(CAN_RADIUS);
  });
});

describe('a glancing stomp', () => {
  it('folds the can away from the pressed side and skids it along the slab', () => {
    expect(glancing.asymmetry).toBeGreaterThan(0.5);
    expect(glancing.foldAngle).toBeGreaterThan(0.5);
    expect(glancing.tipAngle).toBeGreaterThan(0.1);
    expect(glancing.launch).toBeGreaterThan(0);

    // The foot landed to the +X side, so the can escapes towards -X.
    expect(glancing.escapeDir.x).toBeLessThan(-0.5);
    const slide = canDisplacement(glancing, 1);
    expect(slide.x).toBeLessThan(0);
    expect(slide.y).toBe(0);
  });

  it('leans its top over in the escape direction', () => {
    const topPristine = deformCanPoint(0, 1, glancing, 0);
    const topFolded = deformCanPoint(0, 1, glancing, 1);
    expect(topFolded.x).toBeLessThan(topPristine.x - 0.1);
  });

  it('crushes it less than a centred stomp does', () => {
    expect(glancing.heightRatio).toBeGreaterThan(perfect.heightRatio);
    expect(crushAmount(glancing, 1)).toBeLessThan(crushAmount(perfect, 1));
  });
});

describe('a miss', () => {
  it('leaves the can exactly as it was, at every progress value', () => {
    for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
      expect(crushedHeight(missed, progress)).toBeCloseTo(CAN_HEIGHT, 9);
      expect(crushAmount(missed, progress)).toBe(0);
      expect(missed.tipAngle).toBe(0);
      expect(canDisplacement(missed, progress)).toEqual({ x: 0, y: 0, z: 0 });
      const points = sample(missed, progress);
      const reference = sample(missed, 0);
      points.forEach((p, i) => {
        expect(p.x).toBeCloseTo(reference[i]!.x, 12);
        expect(p.y).toBeCloseTo(reference[i]!.y, 12);
        expect(p.z).toBeCloseTo(reference[i]!.z, 12);
      });
    }
  });
});

describe('the animation itself', () => {
  it('shrinks the can monotonically as it plays', () => {
    let previous = Infinity;
    for (let p = 0; p <= 1.0001; p += 0.05) {
      const h = crushedHeight(perfect, p);
      expect(h).toBeLessThanOrEqual(previous + 1e-9);
      previous = h;
    }
  });

  it('never produces a NaN vertex, whatever it is handed', () => {
    for (const outcome of [perfect, glancing, missed]) {
      for (const progress of [-1, 0, 0.5, 1, 2, NaN]) {
        for (const point of sample(outcome, progress)) {
          expect(Number.isFinite(point.x)).toBe(true);
          expect(Number.isFinite(point.y)).toBe(true);
          expect(Number.isFinite(point.z)).toBe(true);
        }
      }
    }
  });

  it('keeps the can above the slab', () => {
    for (const outcome of [perfect, glancing, missed]) {
      for (let p = 0; p <= 1; p += 0.1) {
        for (const point of sample(outcome, p)) {
          expect(point.y).toBeGreaterThanOrEqual(-1e-9);
        }
      }
    }
  });
});
