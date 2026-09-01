import { describe, expect, it } from 'vitest';
import type { BufferGeometry, Mesh } from 'three';
import { CanMesh } from '../src/render/can';
import { crushCan, pristineOutcome } from '../src/domain/crush';
import { CAN_HEIGHT, MIN_HEIGHT_RATIO } from '../src/domain/constants';

/** Highest vertex of the mesh, in the can's own space. */
function meshTop(mesh: CanMesh): number {
  const geometry = (mesh.group.children[0] as Mesh).geometry as BufferGeometry;
  const array = geometry.getAttribute('position').array;
  let top = -Infinity;
  for (let i = 1; i < array.length; i += 3) top = Math.max(top, array[i]!);
  return top;
}

describe('can mesh', () => {
  it('stands where the round put it, and stays there through a clean crush', () => {
    const mesh = new CanMesh();
    mesh.setBase(0.42, -0.19);
    expect(mesh.group.position.x).toBeCloseTo(0.42, 9);
    expect(mesh.group.position.z).toBeCloseTo(-0.19, 9);

    const perfect = crushCan({ offsetX: 0, offsetZ: 0, tiltX: 0, tiltZ: 0, power: 1 });
    for (const progress of [0, 0.3, 0.7, 1]) {
      mesh.update(perfect, progress);
      expect(mesh.group.position.x).toBeCloseTo(0.42, 9);
      expect(mesh.group.position.z).toBeCloseTo(-0.19, 9);
    }
    expect(meshTop(mesh)).toBeCloseTo(CAN_HEIGHT * MIN_HEIGHT_RATIO, 5);
  });

  it('skids away from its mark only when the stomp was lopsided', () => {
    const mesh = new CanMesh();
    mesh.setBase(1, 0);
    const glancing = crushCan({ offsetX: 0.6, offsetZ: 0, tiltZ: 0.3, power: 1 });
    mesh.update(glancing, 1);
    // The foot landed to the +X side, so the can escapes towards -X of its mark.
    expect(mesh.group.position.x).toBeLessThan(1);
    expect(mesh.group.position.y).toBeGreaterThanOrEqual(0);
  });

  it('starts and resets as a pristine, upright can', () => {
    const mesh = new CanMesh();
    mesh.setBase(-0.3, 0.2);
    mesh.update(pristineOutcome(), 0);
    expect(meshTop(mesh)).toBeCloseTo(CAN_HEIGHT, 5);
    expect(mesh.group.quaternion.w).toBeCloseTo(1, 9);
    expect(mesh.group.position.y).toBeCloseTo(0, 9);
    expect(mesh.group.position.x).toBeCloseTo(-0.3, 9);
  });
});
