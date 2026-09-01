/**
 * The foot: a chunky low-poly boot on the end of a leg that runs out of shot.
 *
 * The group's origin sits at the centre of the sole's underside, which is the
 * same point the domain calls the impact position, so posing it is a direct
 * copy of the game state.
 */

import { BoxGeometry, CylinderGeometry, Group, Mesh, MeshStandardMaterial } from 'three';
import { FOOT_HALF_LENGTH, FOOT_HALF_WIDTH } from '../domain/constants';
import { PALETTE } from './palette';

export class Foot {
  readonly group = new Group();

  constructor() {
    const soleMaterial = new MeshStandardMaterial({ color: PALETTE.sole, roughness: 0.85, flatShading: true });
    const treadMaterial = new MeshStandardMaterial({ color: PALETTE.soleTread, roughness: 0.95, flatShading: true });
    const shoeMaterial = new MeshStandardMaterial({ color: PALETTE.shoe, roughness: 0.6, flatShading: true });
    const shoeDarkMaterial = new MeshStandardMaterial({ color: PALETTE.shoeDark, roughness: 0.6, flatShading: true });
    const sockMaterial = new MeshStandardMaterial({ color: PALETTE.sock, roughness: 0.9, flatShading: true });
    const laceMaterial = new MeshStandardMaterial({ color: PALETTE.lace, roughness: 0.8, flatShading: true });
    const midsoleMaterial = new MeshStandardMaterial({ color: PALETTE.midsole, roughness: 0.7, flatShading: true });
    const trouserMaterial = new MeshStandardMaterial({ color: PALETTE.trouser, roughness: 0.95, flatShading: true });
    const cuffMaterial = new MeshStandardMaterial({ color: PALETTE.trouserDark, roughness: 0.95, flatShading: true });

    const width = FOOT_HALF_WIDTH * 2;
    const length = FOOT_HALF_LENGTH * 2;

    const add = (
      mesh: Mesh,
      x: number,
      y: number,
      z: number,
      rotationX = 0,
    ): Mesh => {
      mesh.position.set(x, y, z);
      mesh.rotation.x = rotationX;
      mesh.castShadow = true;
      this.group.add(mesh);
      return mesh;
    };

    // Tread plate, dark sole, then a pale midsole stripe so the sole angle is
    // legible against the concrete.
    add(new Mesh(new BoxGeometry(width * 0.96, 0.07, length * 0.98), treadMaterial), 0, 0.035, 0);
    add(new Mesh(new BoxGeometry(width, 0.1, length), soleMaterial), 0, 0.12, 0);
    add(new Mesh(new BoxGeometry(width * 1.02, 0.1, length * 1.01), midsoleMaterial), 0, 0.22, 0);

    // Grip bars, so the sole reads as a shoe and its angle is legible.
    for (let i = -2; i <= 2; i++) {
      add(new Mesh(new BoxGeometry(width * 0.86, 0.05, 0.1), treadMaterial), 0, 0.012, i * 0.3);
    }

    // Upper: a heel block, an instep, and a chamfered toe cap.
    add(new Mesh(new BoxGeometry(width * 0.94, 0.44, length * 0.4), shoeMaterial), 0, 0.5, length * 0.28);
    add(new Mesh(new BoxGeometry(width * 0.9, 0.32, length * 0.34), shoeMaterial), 0, 0.43, 0);
    add(new Mesh(new BoxGeometry(width * 0.86, 0.22, length * 0.3), shoeDarkMaterial), 0, 0.36, -length * 0.27, -0.24);
    add(new Mesh(new BoxGeometry(width * 0.8, 0.12, length * 0.16), midsoleMaterial), 0, 0.33, -length * 0.42, -0.24);

    // Laces and a heel tab.
    for (let i = 0; i < 3; i++) {
      add(new Mesh(new BoxGeometry(width * 0.46, 0.04, 0.07), laceMaterial), 0, 0.58 - i * 0.02, 0.02 + i * 0.15);
    }
    add(new Mesh(new BoxGeometry(width * 0.5, 0.14, 0.07), shoeDarkMaterial), 0, 0.72, length * 0.46);

    // Ankle, then a trouser leg that leaves the top of the frame. Kept slim
    // and a different colour so it never reads as part of the shoe.
    add(new Mesh(new CylinderGeometry(0.24, 0.28, 0.26, 10), sockMaterial), 0, 0.8, length * 0.18);
    add(new Mesh(new CylinderGeometry(0.22, 0.26, 0.18, 10), cuffMaterial), 0, 0.98, length * 0.18);
    add(new Mesh(new CylinderGeometry(0.19, 0.23, 1.5, 10), trouserMaterial), 0, 1.8, length * 0.18);
  }

  /** Places the sole centre and sets the two tilt angles, in radians. */
  setPose(x: number, y: number, z: number, tiltX: number, tiltZ: number): void {
    this.group.position.set(x, y, z);
    this.group.rotation.set(tiltX, 0, tiltZ);
  }

  /** Squash and stretch during the wind-up and the slam. */
  setSquash(scaleY: number): void {
    this.group.scale.set(1 + (1 - scaleY) * 0.35, scaleY, 1 + (1 - scaleY) * 0.35);
  }
}
