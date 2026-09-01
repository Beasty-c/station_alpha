import { describe, expect, it } from 'vitest';
import { PerspectiveCamera } from 'three';
import { groundPointAt } from '../src/render/pick';
import { pointerToNdc } from '../src/domain/input';
import { AIM_LIMIT_X, AIM_LIMIT_Z } from '../src/domain/constants';

/** A camera set up the way the game frames a landscape desktop view. */
function gameCamera(): PerspectiveCamera {
  const camera = new PerspectiveCamera(38, 1280 / 800, 0.1, 60);
  camera.position.set(0, 3.1, 6.2);
  camera.lookAt(0, 0.75, 0);
  camera.updateMatrixWorld(true);
  camera.updateProjectionMatrix();
  return camera;
}

const rect = { left: 0, top: 0, width: 1280, height: 800 };

describe('aiming at the slab', () => {
  it('lands the aim under the pointer, not at a guessed offset', () => {
    const camera = gameCamera();
    const centre = groundPointAt(camera, pointerToNdc(640, 400, rect));
    expect(centre).not.toBeNull();
    // The camera looks slightly above the slab centre, so the ray through the
    // middle of the screen lands a little beyond it, but on the axis.
    expect(Math.abs(centre!.x)).toBeLessThan(1e-6);
    expect(centre!.z).toBeLessThan(1);
  });

  it('moves the aim right when the pointer moves right', () => {
    const camera = gameCamera();
    const left = groundPointAt(camera, pointerToNdc(300, 500, rect))!;
    const right = groundPointAt(camera, pointerToNdc(980, 500, rect))!;
    expect(left.x).toBeLessThan(0);
    expect(right.x).toBeGreaterThan(0);
  });

  it('moves the aim away from the camera when the pointer moves up', () => {
    const camera = gameCamera();
    const near = groundPointAt(camera, pointerToNdc(640, 700, rect))!;
    const far = groundPointAt(camera, pointerToNdc(640, 300, rect))!;
    expect(far.z).toBeLessThan(near.z);
  });

  it('keeps the aim on the reachable part of the slab', () => {
    const camera = gameCamera();
    for (const [x, y] of [
      [0, 0],
      [1279, 0],
      [0, 799],
      [1279, 799],
      [640, 799],
    ] as const) {
      const point = groundPointAt(camera, pointerToNdc(x, y, rect))!;
      expect(point).not.toBeNull();
      expect(Math.abs(point.x)).toBeLessThanOrEqual(AIM_LIMIT_X);
      expect(Math.abs(point.z)).toBeLessThanOrEqual(AIM_LIMIT_Z);
    }
  });

  it('returns null rather than a wild point when the ray misses the ground', () => {
    const camera = new PerspectiveCamera(38, 1.6, 0.1, 60);
    camera.position.set(0, 3, 6);
    camera.lookAt(0, 20, 0);
    camera.updateMatrixWorld(true);
    expect(groundPointAt(camera, { x: 0, y: 0 })).toBeNull();
  });
});
