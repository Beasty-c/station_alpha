/**
 * Turns a pointer into a point on the slab.
 *
 * Aiming has to be literal: wherever the player puts the cursor or their
 * finger is where the foot goes. That means casting the camera ray at the
 * ground plane rather than guessing a linear mapping from screen space.
 */

import { Plane, Raycaster, Vector2, Vector3, type PerspectiveCamera } from 'three';
import { clampAim, type Aim, type Ndc } from '../domain/input';

const GROUND = new Plane(new Vector3(0, 1, 0), 0);
const raycaster = new Raycaster();
const pointer = new Vector2();
const hit = new Vector3();

/**
 * @returns the clamped slab point under the pointer, or null when the ray
 *          misses the ground entirely (a pointer above the horizon).
 */
export function groundPointAt(camera: PerspectiveCamera, ndc: Ndc): Aim | null {
  pointer.set(ndc.x, ndc.y);
  raycaster.setFromCamera(pointer, camera);
  if (!raycaster.ray.intersectPlane(GROUND, hit)) return null;
  return clampAim({ x: hit.x, z: hit.z });
}
