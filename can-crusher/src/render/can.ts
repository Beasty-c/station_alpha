/**
 * The can mesh.
 *
 * A ring lattice whose vertices are placed by `deformCanPoint`, so the shape
 * on screen is literally the shape the scoring engine measured.
 */

import {
  BufferAttribute,
  BufferGeometry,
  Group,
  Mesh,
  MeshStandardMaterial,
  Quaternion,
  Vector3,
  type Material,
} from 'three';
import { CAN_HEIGHT, CAN_RADIUS } from '../domain/constants';
import { canDisplacement, deformCanPoint } from '../domain/canShape';
import { pristineOutcome } from '../domain/crush';
import type { CrushOutcome } from '../domain/types';
import { PALETTE } from './palette';

const RADIAL = 22;
const STACKS = 18;

const tipAxis = new Vector3();
const pivot = new Vector3();
const rotatedPivot = new Vector3();
const tipRotation = new Quaternion();

/** Rows that carry the painted band, so the crush is easy to read. */
function isBandRow(v: number): boolean {
  return v > 0.3 && v < 0.62;
}

export class CanMesh {
  readonly group = new Group();
  private readonly body: Mesh;
  private readonly geometry: BufferGeometry;
  private readonly positions: Float32Array;
  private readonly colors: Float32Array;
  private outcome: CrushOutcome = pristineOutcome();
  private progress = 0;
  /** Where on the slab this round's can is standing. */
  private baseX = 0;
  private baseZ = 0;

  constructor() {
    const vertexCount = (STACKS + 1) * (RADIAL + 1) + 2;
    this.positions = new Float32Array(vertexCount * 3);
    this.colors = new Float32Array(vertexCount * 3);

    const indices: number[] = [];
    for (let j = 0; j < STACKS; j++) {
      for (let i = 0; i < RADIAL; i++) {
        const a = j * (RADIAL + 1) + i;
        const b = a + RADIAL + 1;
        indices.push(a, b, a + 1, b, b + 1, a + 1);
      }
    }
    // Fans for the lid and the base.
    const lidCentre = (STACKS + 1) * (RADIAL + 1);
    const baseCentre = lidCentre + 1;
    // Wound so the lid faces up and the base faces down: the fans are the
    // mirror of the body quads, not a repeat of them.
    for (let i = 0; i < RADIAL; i++) {
      indices.push(lidCentre, STACKS * (RADIAL + 1) + i + 1, STACKS * (RADIAL + 1) + i);
      indices.push(baseCentre, i, i + 1);
    }

    this.geometry = new BufferGeometry();
    this.geometry.setAttribute('position', new BufferAttribute(this.positions, 3));
    this.geometry.setAttribute('color', new BufferAttribute(this.colors, 3));
    this.geometry.setIndex(indices);
    this.writeColors();

    const material = new MeshStandardMaterial({
      vertexColors: true,
      // Enough sheen to read as aluminium, but not so metallic that it goes
      // black without an environment map to reflect.
      metalness: 0.28,
      roughness: 0.4,
      flatShading: true,
    });
    this.body = new Mesh(this.geometry, material);
    this.body.castShadow = true;
    this.body.receiveShadow = true;
    this.group.add(this.body);

    this.update(this.outcome, 0);
  }

  /** Colours are baked once: aluminium body with an unbranded painted band. */
  private writeColors(): void {
    const write = (index: number, hex: number) => {
      const r = ((hex >> 16) & 255) / 255;
      const g = ((hex >> 8) & 255) / 255;
      const b = (hex & 255) / 255;
      this.colors[index * 3] = r;
      this.colors[index * 3 + 1] = g;
      this.colors[index * 3 + 2] = b;
    };
    for (let j = 0; j <= STACKS; j++) {
      const v = j / STACKS;
      for (let i = 0; i <= RADIAL; i++) {
        const index = j * (RADIAL + 1) + i;
        if (isBandRow(v)) write(index, v < 0.36 || v > 0.56 ? PALETTE.canBandDark : PALETTE.canBand);
        else write(index, v > 0.9 || v < 0.06 ? PALETTE.aluminiumDark : PALETTE.aluminium);
      }
    }
    write((STACKS + 1) * (RADIAL + 1), PALETTE.aluminiumDark);
    write((STACKS + 1) * (RADIAL + 1) + 1, PALETTE.aluminiumDark);
  }

  /**
   * Moves the can to where this round's can stands. The crush animation is
   * applied relative to this point, so the can never jumps off its mark.
   */
  setBase(x: number, z: number): void {
    this.baseX = x;
    this.baseZ = z;
    this.update(this.outcome, this.progress);
  }

  /** Rebuilds the mesh for an outcome at a point in its crush animation. */
  update(outcome: CrushOutcome, progress: number): void {
    this.outcome = outcome;
    this.progress = progress;

    let lidX = 0;
    let lidY = 0;
    let lidZ = 0;
    let baseY = 0;

    for (let j = 0; j <= STACKS; j++) {
      const v = j / STACKS;
      for (let i = 0; i <= RADIAL; i++) {
        const theta = (i / RADIAL) * Math.PI * 2;
        const point = deformCanPoint(theta, v, outcome, progress);
        const index = (j * (RADIAL + 1) + i) * 3;
        this.positions[index] = point.x;
        this.positions[index + 1] = point.y;
        this.positions[index + 2] = point.z;
        if (j === STACKS && i < RADIAL) {
          lidX += point.x;
          lidY += point.y;
          lidZ += point.z;
        }
        if (j === 0 && i === 0) baseY = point.y;
      }
    }

    const lidCentre = (STACKS + 1) * (RADIAL + 1);
    this.positions[lidCentre * 3] = lidX / RADIAL;
    this.positions[lidCentre * 3 + 1] = lidY / RADIAL;
    this.positions[lidCentre * 3 + 2] = lidZ / RADIAL;
    this.positions[(lidCentre + 1) * 3] = 0;
    this.positions[(lidCentre + 1) * 3 + 1] = baseY;
    this.positions[(lidCentre + 1) * 3 + 2] = 0;

    this.geometry.getAttribute('position').needsUpdate = true;
    this.geometry.computeVertexNormals();
    this.geometry.computeBoundingSphere();

    // A toppling can pivots on the base rim it is falling over, so the mesh is
    // rotated about that point rather than about its own centre — otherwise it
    // would sink through the slab on one side.
    const p = Math.min(1, Math.max(0, progress));
    const tip = outcome.tipAngle * p;
    tipAxis.set(outcome.escapeDir.z, 0, -outcome.escapeDir.x);
    if (tipAxis.lengthSq() < 1e-9 || tip === 0) {
      this.group.quaternion.identity();
      rotatedPivot.set(0, 0, 0);
      pivot.set(0, 0, 0);
    } else {
      tipAxis.normalize();
      tipRotation.setFromAxisAngle(tipAxis, tip);
      this.group.quaternion.copy(tipRotation);
      pivot.set(outcome.escapeDir.x * CAN_RADIUS, 0, outcome.escapeDir.z * CAN_RADIUS);
      rotatedPivot.copy(pivot).applyQuaternion(tipRotation);
    }

    const slide = canDisplacement(outcome, progress);
    this.group.position.set(
      this.baseX + slide.x + pivot.x - rotatedPivot.x,
      pivot.y - rotatedPivot.y,
      this.baseZ + slide.z + pivot.z - rotatedPivot.z,
    );
  }

  /** Height of the can right now, for parking the foot on top of it. */
  get topHeight(): number {
    return CAN_HEIGHT * (1 - (1 - this.outcome.heightRatio) * Math.min(1, Math.max(0, this.progress)));
  }

  dispose(): void {
    this.geometry.dispose();
    (this.body.material as Material).dispose();
  }
}
