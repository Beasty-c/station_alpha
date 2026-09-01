/**
 * Impact garnish: dust, a shock ring, and camera shake.
 *
 * All of it scales down to nothing when the player prefers reduced motion, and
 * none of it is load-bearing for reading the result.
 */

import {
  AdditiveBlending,
  BufferAttribute,
  BufferGeometry,
  Group,
  Mesh,
  MeshBasicMaterial,
  Points,
  PointsMaterial,
  RingGeometry,
  type PerspectiveCamera,
} from 'three';
import { PALETTE } from './palette';

const PARTICLES = 44;

interface Particle {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
}

export class ImpactEffects {
  readonly group = new Group();
  private readonly points: Points;
  private readonly positions: Float32Array;
  private readonly particles: Particle[] = [];
  private readonly ring: Mesh;
  private readonly ringMaterial: MeshBasicMaterial;
  private readonly dustMaterial: PointsMaterial;
  private life = 0;
  private duration = 1;
  private shake = 0;

  constructor() {
    this.positions = new Float32Array(PARTICLES * 3);
    const geometry = new BufferGeometry();
    geometry.setAttribute('position', new BufferAttribute(this.positions, 3));
    this.dustMaterial = new PointsMaterial({
      color: PALETTE.dust,
      size: 0.14,
      sizeAttenuation: true,
      transparent: true,
      opacity: 0,
      depthWrite: false,
    });
    this.points = new Points(geometry, this.dustMaterial);
    this.points.frustumCulled = false;
    this.group.add(this.points);

    this.ringMaterial = new MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: 0,
      depthWrite: false,
      blending: AdditiveBlending,
    });
    this.ring = new Mesh(new RingGeometry(0.4, 0.62, 28), this.ringMaterial);
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.position.y = 0.02;
    this.ring.visible = false;
    this.group.add(this.ring);

    for (let i = 0; i < PARTICLES; i++) {
      this.particles.push({ x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0 });
    }
  }

  /**
   * Fires the burst. `strength` is 0 to 1; `reducedMotion` keeps the dust but
   * drops the shake and shortens everything.
   */
  burst(x: number, z: number, strength: number, reducedMotion: boolean): void {
    const scale = Math.max(0.15, strength);
    this.duration = reducedMotion ? 0.4 : 0.75;
    this.life = this.duration;
    this.shake = reducedMotion ? 0 : 0.16 * scale;

    this.group.position.set(x, 0, z);
    this.ring.visible = true;
    this.ring.scale.setScalar(0.6);
    this.ringMaterial.opacity = 0.55 * scale;

    for (let i = 0; i < PARTICLES; i++) {
      const particle = this.particles[i]!;
      const angle = (i / PARTICLES) * Math.PI * 2 + Math.random() * 0.4;
      const speed = (1.4 + Math.random() * 1.7) * (0.45 + scale * 0.55);
      particle.x = Math.cos(angle) * 0.3;
      particle.y = 0.05;
      particle.z = Math.sin(angle) * 0.3;
      particle.vx = Math.cos(angle) * speed;
      particle.vy = 0.9 + Math.random() * 1.5 * scale;
      particle.vz = Math.sin(angle) * speed;
    }
    this.dustMaterial.opacity = 0.85;
  }

  /** Advances the effects and applies the shake to the camera. */
  update(dt: number, camera: PerspectiveCamera): void {
    if (this.life <= 0) return;
    this.life = Math.max(0, this.life - dt);
    const t = this.life / this.duration;

    for (let i = 0; i < PARTICLES; i++) {
      const particle = this.particles[i]!;
      particle.vy -= 6.2 * dt;
      particle.x += particle.vx * dt;
      particle.y = Math.max(0.02, particle.y + particle.vy * dt);
      particle.z += particle.vz * dt;
      particle.vx *= 1 - 2.6 * dt;
      particle.vz *= 1 - 2.6 * dt;
      this.positions[i * 3] = particle.x;
      this.positions[i * 3 + 1] = particle.y;
      this.positions[i * 3 + 2] = particle.z;
    }
    this.points.geometry.getAttribute('position').needsUpdate = true;
    this.dustMaterial.opacity = 0.85 * t;

    const grow = 1 + (1 - t) * 3.4;
    this.ring.scale.setScalar(grow);
    this.ringMaterial.opacity = 0.55 * t * t;
    if (this.life === 0) this.ring.visible = false;

    if (this.shake > 0) {
      const amount = this.shake * t * t;
      camera.position.x += (Math.random() - 0.5) * amount * 2;
      camera.position.y += (Math.random() - 0.5) * amount * 2;
    }
  }

  reset(): void {
    this.life = 0;
    this.shake = 0;
    this.dustMaterial.opacity = 0;
    this.ringMaterial.opacity = 0;
    this.ring.visible = false;
  }
}
