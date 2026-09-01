/**
 * The workshop: slab, crates, lights and camera.
 *
 * Everything is procedural, so there are no art assets to download and the
 * whole scene costs a few hundred triangles.
 */

import {
  AmbientLight,
  BoxGeometry,
  CircleGeometry,
  Color,
  CylinderGeometry,
  DirectionalLight,
  Fog,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  RingGeometry,
  Scene,
  WebGLRenderer,
  type WebGLRendererParameters,
} from 'three';
import { PALETTE } from './palette';
import { AIM_LIMIT_X } from '../domain/constants';

export interface Stage {
  renderer: WebGLRenderer;
  scene: Scene;
  camera: PerspectiveCamera;
  /** Parent of everything that shakes on impact. */
  world: Group;
  reticle: Group;
  /** Shared material for the reticle, so its glow can be animated. */
  reticleMaterial: MeshBasicMaterial;
  /** Ring painted on the slab around where the can is standing. */
  targetRing: Mesh;
  canShadow: Mesh;
  resize(width: number, height: number): void;
  dispose(): void;
}

/** Keeps the whole slab in shot on any aspect ratio, portrait included. */
function frameCamera(camera: PerspectiveCamera, width: number, height: number): void {
  const aspect = width / Math.max(1, height);
  camera.aspect = aspect;
  // Portrait phones need a longer lens and more distance to keep the can,
  // the foot and the landing area all on screen at once.
  const portrait = aspect < 0.95;
  // A landscape phone has almost no vertical room, so the shot is flatter and
  // aimed lower, which lifts the can clear of the score card along the bottom.
  const shortLandscape = aspect > 1.9;

  camera.fov = portrait ? 50 : 38;
  // Far enough back that the boot stays in shot wherever the player aims it.
  const distance = portrait ? 7.6 : shortLandscape ? 6.6 : 6.2 - Math.min(0.7, (aspect - 0.95) * 0.5);
  const height3d = portrait ? 3.6 : shortLandscape ? 2.7 : 3.05;
  camera.position.set(0, height3d, distance);
  camera.lookAt(0, shortLandscape ? 0.55 : 0.9, 0);
  camera.updateProjectionMatrix();
}

function buildSlab(): Group {
  const group = new Group();

  const slab = new Mesh(
    new PlaneGeometry(26, 26),
    new MeshStandardMaterial({ color: PALETTE.slab, roughness: 0.95, metalness: 0 }),
  );
  slab.rotation.x = -Math.PI / 2;
  slab.receiveShadow = true;
  group.add(slab);

  // Expansion joints, so the ground reads as a concrete floor and gives the
  // eye something to judge the foot's position against.
  const lineMaterial = new MeshBasicMaterial({ color: PALETTE.slabLine, transparent: true, opacity: 0.35 });
  for (let i = -3; i <= 3; i++) {
    for (const axis of [0, 1]) {
      const line = new Mesh(new PlaneGeometry(axis ? 0.045 : 26, axis ? 26 : 0.045), lineMaterial);
      line.rotation.x = -Math.PI / 2;
      line.position.set(axis ? i * 2.6 : 0, 0.002, axis ? 0 : i * 2.6);
      group.add(line);
    }
  }

  // A kerb and a workshop wall behind the play area, to close the composition
  // off and stop the background reading as empty sky.
  const kerb = new Mesh(
    new BoxGeometry(26, 0.42, 0.7),
    new MeshStandardMaterial({ color: PALETTE.slabEdge, roughness: 0.9 }),
  );
  kerb.position.set(0, 0.21, -5.4);
  kerb.castShadow = true;
  kerb.receiveShadow = true;
  group.add(kerb);

  const wall = new Mesh(
    new BoxGeometry(26, 6, 0.5),
    new MeshStandardMaterial({ color: PALETTE.wall, roughness: 0.98 }),
  );
  wall.position.set(0, 3, -6);
  wall.receiveShadow = true;
  group.add(wall);

  // A skirting band so the wall meets the floor with a readable line.
  const skirting = new Mesh(
    new BoxGeometry(26, 0.6, 0.14),
    new MeshStandardMaterial({ color: PALETTE.wallDark, roughness: 0.95 }),
  );
  skirting.position.set(0, 0.3, -5.72);
  group.add(skirting);

  // Two crates for depth. Low-poly, deliberately chunky, no textures.
  const crateGeometry = new BoxGeometry(1, 1, 1);
  const crateMaterials = [
    new MeshStandardMaterial({ color: PALETTE.crate, roughness: 0.85 }),
    new MeshStandardMaterial({ color: PALETTE.crateDark, roughness: 0.85 }),
  ];
  const crates: [number, number, number, number, number][] = [
    [-4.6, 0.6, -4.2, 1.2, 0],
    [-3.7, 0.35, -4.6, 0.7, 1],
    [4.9, 0.75, -4.1, 1.5, 1],
  ];
  for (const [x, y, z, scale, material] of crates) {
    const crate = new Mesh(crateGeometry, crateMaterials[material]);
    crate.position.set(x, y, z);
    crate.scale.setScalar(scale);
    crate.rotation.y = x * 0.31;
    crate.castShadow = true;
    crate.receiveShadow = true;
    group.add(crate);
  }

  return group;
}

/** The ring on the slab that shows where the sole centre currently is. */
function buildReticle(): { group: Group; material: MeshBasicMaterial } {
  const group = new Group();
  const material = new MeshBasicMaterial({
    color: PALETTE.reticle,
    transparent: true,
    opacity: 0.85,
    depthWrite: false,
  });
  const ring = new Mesh(new RingGeometry(0.26, 0.32, 24), material);
  ring.rotation.x = -Math.PI / 2;
  group.add(ring);

  for (let i = 0; i < 4; i++) {
    const tick = new Mesh(new PlaneGeometry(0.16, 0.05), material);
    tick.rotation.x = -Math.PI / 2;
    tick.rotation.z = (i * Math.PI) / 2;
    const angle = (i * Math.PI) / 2;
    tick.position.set(Math.cos(angle) * 0.45, 0, Math.sin(angle) * 0.45);
    group.add(tick);
  }

  group.position.y = 0.006;
  return { group, material };
}

export function createStage(canvas: HTMLCanvasElement, lowPower: boolean): Stage {
  const parameters: WebGLRendererParameters = {
    canvas,
    antialias: !lowPower,
    powerPreference: 'high-performance',
    alpha: false,
  };
  const renderer = new WebGLRenderer(parameters);
  renderer.shadowMap.enabled = true;
  renderer.setClearColor(new Color(PALETTE.air));

  const scene = new Scene();
  scene.background = new Color(PALETTE.air);
  scene.fog = new Fog(PALETTE.air, 12, 26);

  const camera = new PerspectiveCamera(38, 1, 0.1, 60);

  const world = new Group();
  scene.add(world);
  world.add(buildSlab());

  scene.add(new AmbientLight(0xffffff, 0.55));

  const key = new DirectionalLight(0xfff3e0, 2.1);
  key.position.set(3.6, 6.4, 3.2);
  key.castShadow = true;
  key.shadow.mapSize.set(lowPower ? 512 : 1024, lowPower ? 512 : 1024);
  key.shadow.camera.left = -AIM_LIMIT_X - 1.5;
  key.shadow.camera.right = AIM_LIMIT_X + 1.5;
  key.shadow.camera.top = 4;
  key.shadow.camera.bottom = -3;
  key.shadow.camera.near = 1;
  key.shadow.camera.far = 16;
  key.shadow.bias = -0.0012;
  key.shadow.normalBias = 0.02;
  scene.add(key);
  scene.add(key.target);

  const fill = new DirectionalLight(0xc9d8ff, 0.5);
  fill.position.set(-4, 3, -2.5);
  scene.add(fill);

  // A painted contact shadow under the can keeps it anchored even where the
  // shadow map is coarse.
  const canShadow = new Mesh(
    new CircleGeometry(0.42, 20),
    new MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.24, depthWrite: false }),
  );
  canShadow.rotation.x = -Math.PI / 2;
  canShadow.position.y = 0.004;
  world.add(canShadow);

  // A painted ring around the can's footprint: the player is aiming at a spot
  // on the floor, so the floor should say where that spot is.
  const targetRing = new Mesh(
    new RingGeometry(0.44, 0.5, 28),
    new MeshBasicMaterial({ color: 0x2b2f33, transparent: true, opacity: 0.32, depthWrite: false }),
  );
  targetRing.rotation.x = -Math.PI / 2;
  targetRing.position.y = 0.005;
  world.add(targetRing);

  const reticle = buildReticle();
  world.add(reticle.group);

  // A stub of pipe by the kerb, purely to give the eye a sense of scale.
  const pipe = new Mesh(
    new CylinderGeometry(0.16, 0.16, 3.4, 10),
    new MeshStandardMaterial({ color: PALETTE.slabEdge, roughness: 0.7, metalness: 0.3 }),
  );
  pipe.rotation.z = Math.PI / 2;
  pipe.position.set(2.4, 0.66, -4.9);
  pipe.castShadow = true;
  world.add(pipe);

  function resize(width: number, height: number): void {
    const dpr = Math.min(window.devicePixelRatio || 1, lowPower ? 1.25 : 2);
    renderer.setPixelRatio(dpr);
    renderer.setSize(width, height, false);
    frameCamera(camera, width, height);
  }

  function dispose(): void {
    renderer.dispose();
    scene.traverse((object) => {
      const mesh = object as Mesh;
      if (mesh.geometry) mesh.geometry.dispose();
      const material = mesh.material;
      if (Array.isArray(material)) material.forEach((m) => m.dispose());
      else if (material) material.dispose();
    });
  }

  return {
    renderer,
    scene,
    camera,
    world,
    reticle: reticle.group,
    reticleMaterial: reticle.material,
    targetRing,
    canShadow,
    resize,
    dispose,
  };
}
