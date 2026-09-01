import { describe, expect, it } from 'vitest';
import {
  IMPACT_AT,
  PHASES,
  REVEAL_AT,
  STOMP_DURATION,
  stompFrame,
} from '../src/render/timeline';
import { crushCan } from '../src/domain/crush';
import { CAN_HEIGHT } from '../src/domain/constants';

const hover = 0.42;
const hit = crushCan({ offsetX: 0, offsetZ: 0, tiltX: 0, tiltZ: 0, power: 1 });
const missed = crushCan({ offsetX: 3, power: 1 });

const at = (t: number, previous = t - 1 / 60) => stompFrame(t, previous, hover, hit);

describe('stomp timeline', () => {
  it('winds up before it drops', () => {
    const rest = CAN_HEIGHT + hover;
    expect(at(0).footY).toBeCloseTo(rest, 6);
    expect(at(PHASES.anticipate).footY).toBeGreaterThan(rest);
    expect(at(PHASES.anticipate).squash).toBeGreaterThan(1);
  });

  it('meets the can exactly at the impact moment', () => {
    expect(at(IMPACT_AT).footY).toBeCloseTo(CAN_HEIGHT, 6);
    expect(at(IMPACT_AT).crush).toBeCloseTo(0, 9);
  });

  it('reports the impact on exactly one frame', () => {
    let fired = 0;
    let previous = 0;
    for (let t = 0; t <= STOMP_DURATION; t += 1 / 60) {
      if (stompFrame(t, previous, hover, hit).impact) fired++;
      previous = t;
    }
    expect(fired).toBe(1);
  });

  it('rides the can down as it crushes and stops on top of it', () => {
    const mid = at(IMPACT_AT + PHASES.crush / 2);
    expect(mid.crush).toBeGreaterThan(0);
    expect(mid.crush).toBeLessThan(1);
    expect(mid.footY).toBeLessThan(CAN_HEIGHT);
    expect(mid.footY).toBeGreaterThan(CAN_HEIGHT * hit.heightRatio);
    expect(at(REVEAL_AT).footY).toBeCloseTo(CAN_HEIGHT * hit.heightRatio, 6);
  });

  it('carries the foot to the slab when the stomp misses', () => {
    const frame = stompFrame(IMPACT_AT, IMPACT_AT - 0.01, hover, missed);
    expect(frame.footY).toBeCloseTo(0, 6);
    expect(stompFrame(REVEAL_AT, REVEAL_AT - 0.01, hover, missed).crush).toBe(1);
  });

  it('shows the score once the can has settled, then withdraws the foot', () => {
    expect(at(REVEAL_AT - 0.01).reveal).toBe(false);
    expect(at(REVEAL_AT).reveal).toBe(true);
    expect(at(STOMP_DURATION).done).toBe(true);
    expect(at(STOMP_DURATION).footY).toBeCloseTo(CAN_HEIGHT + hover, 6);
  });

  it('is continuous: no jumps between phases', () => {
    let previousY = at(0).footY;
    for (let t = 0; t <= STOMP_DURATION; t += 1 / 120) {
      const y = at(t).footY;
      expect(Math.abs(y - previousY)).toBeLessThan(0.2);
      previousY = y;
    }
  });

  it('clamps time outside the sequence rather than extrapolating', () => {
    expect(at(-5).footY).toBeCloseTo(CAN_HEIGHT + hover, 6);
    const late = at(STOMP_DURATION + 10);
    expect(late.done).toBe(true);
    expect(late.footY).toBeCloseTo(CAN_HEIGHT + hover, 6);
    expect(late.crush).toBe(1);
  });
});
