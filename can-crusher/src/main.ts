/**
 * Wiring: input → game state → scene.
 *
 * The loop is deliberately thin. Anything that decides something about the
 * game lives in `src/domain`; anything that draws lives in `src/render`.
 */

import { CAN_HEIGHT } from './domain/constants';
import {
  aimKeyFor,
  applyKeyboardAim,
  emptyKeys,
  isStompKey,
  MAX_FRAME_STEP,
  pointerToNdc,
} from './domain/input';
import {
  beginPlay,
  createGame,
  nextRound,
  revealResult,
  setAim,
  setMuted,
  setPaused,
  setReducedMotion,
  solePosition,
  stomp,
  tick,
  type GameState,
} from './domain/game';
import { nextPerfectInstant, windowCloseness, wobbleAt } from './domain/wobble';
import { CanMesh } from './render/can';
import { ImpactEffects } from './render/effects';
import { Foot } from './render/foot';
import { groundPointAt } from './render/pick';
import { createStage } from './render/scene';
import { STOMP_DURATION, stompFrame } from './render/timeline';
import { GameAudio } from './audio';
import { loadSession, saveSession } from './storage';
import { Hud } from './ui/hud';

function boot(): void {
  const element = document.getElementById('stage');
  if (!(element instanceof HTMLCanvasElement)) throw new Error('Missing #stage canvas');
  const canvas: HTMLCanvasElement = element;

  const saved = loadSession();
  let state: GameState = createGame(Math.floor(Math.random() * 0x7fffffff) + 1, {
    best: saved.best,
    muted: saved.muted,
    tutorialDone: saved.tutorialDone,
    reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false,
  });
  if (saved.tutorialDone) state = beginPlay(state);

  const audio = new GameAudio();
  const keys = emptyKeys();

  const hud = new Hud({
    onRetry: () => startNextRound(),
    onToggleMute: () => {
      audio.unlock();
      state = setMuted(state, !state.muted);
      audio.setMuted(state.muted);
      persist();
      hud.render(state);
    },
    onTogglePause: () => {
      const next = setPaused(state, !state.paused);
      if (next === state) return;
      state = next;
      hud.render(state);
    },
    onToggleMotion: () => {
      state = setReducedMotion(state, !state.reducedMotion);
      hud.render(state);
    },
    onDismissIntro: () => {
      audio.unlock();
      state = beginPlay(state);
      persist();
      hud.render(state);
    },
  });

  // Low-power devices get a smaller shadow map and no antialiasing.
  const lowPower =
    (navigator.hardwareConcurrency ?? 8) <= 4 ||
    Math.min(window.screen?.width ?? 1024, window.screen?.height ?? 768) < 420;

  let stage: ReturnType<typeof createStage>;
  try {
    stage = createStage(canvas, lowPower);
  } catch {
    hud.showError(
      'This browser could not start WebGL, which Can Crusher needs to draw the scene. Try enabling hardware acceleration, or open the game in a different browser.',
    );
    return;
  }

  const can = new CanMesh();
  const foot = new Foot();
  const effects = new ImpactEffects();
  stage.world.add(can.group, foot.group, effects.group);

  /** Non-null while a stomp animation is playing. */
  let animation: { elapsed: number; previous: number; hoverY: number } | null = null;
  let revealed = false;

  function persist(): void {
    saveSession({ best: state.best, muted: state.muted, tutorialDone: state.tutorialDone });
  }

  function startNextRound(): void {
    state = nextRound(state);
    animation = null;
    revealed = false;
    effects.reset();
    can.setBase(state.canX, state.canZ);
    can.update(state.outcome, 0);
    hud.render(state);
  }

  function triggerStomp(): void {
    audio.unlock();
    if (state.paused) return;
    if (state.phase === 'result') {
      startNextRound();
      return;
    }
    const next = stomp(state);
    if (next === state) return;
    const hover = wobbleAt(state.clock, state.seed).hover;
    state = next;
    animation = { elapsed: 0, previous: -1, hoverY: hover };
    revealed = false;
    persist();
    audio.play('whoosh');
    hud.render(state);
  }

  // ---- input -------------------------------------------------------------

  function aimFromPointer(event: { clientX: number; clientY: number }): void {
    const ndc = pointerToNdc(event.clientX, event.clientY, canvas.getBoundingClientRect());
    const point = groundPointAt(stage.camera, ndc);
    // A pointer above the horizon has nowhere to land; keep the current aim.
    if (point) state = setAim(state, point);
  }

  canvas.addEventListener('pointermove', (event) => {
    if (event.pointerType === 'touch' && event.buttons === 0) return;
    aimFromPointer(event);
  });
  canvas.addEventListener('pointerdown', (event) => {
    canvas.setPointerCapture?.(event.pointerId);
    aimFromPointer(event);
    // A touch aims on press and stomps on release, so the player can slide a
    // finger into position before committing.
    if (event.pointerType !== 'touch') triggerStomp();
  });
  canvas.addEventListener('pointerup', (event) => {
    if (event.pointerType === 'touch') triggerStomp();
  });
  // Belt and braces against page scroll, zoom and text selection on touch.
  for (const type of ['touchstart', 'touchmove', 'touchend', 'gesturestart', 'contextmenu']) {
    canvas.addEventListener(type, (event) => event.preventDefault(), { passive: false });
  }

  window.addEventListener('keydown', (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const aimKey = aimKeyFor(event.code);
    if (aimKey) {
      keys[aimKey] = true;
      event.preventDefault();
      return;
    }
    if (isStompKey(event.code)) {
      // Space on a focused button would fire twice.
      if (document.activeElement instanceof HTMLButtonElement) return;
      event.preventDefault();
      triggerStomp();
      return;
    }
    if (event.code === 'KeyM') {
      audio.unlock();
      state = setMuted(state, !state.muted);
      audio.setMuted(state.muted);
      persist();
      hud.render(state);
    } else if (event.code === 'KeyP' || event.code === 'Escape') {
      const next = setPaused(state, !state.paused);
      if (next !== state) {
        state = next;
        hud.render(state);
      }
    } else if (event.code === 'KeyR') {
      if (state.phase === 'result') startNextRound();
    }
  });
  window.addEventListener('keyup', (event) => {
    const aimKey = aimKeyFor(event.code);
    if (aimKey) keys[aimKey] = false;
  });

  // Losing focus mid-round should not cost the player a stomp.
  const pauseOnHide = () => {
    if (document.hidden) {
      const next = setPaused(state, true);
      if (next !== state) {
        state = next;
        hud.render(state);
      }
    }
  };
  document.addEventListener('visibilitychange', pauseOnHide);
  window.addEventListener('blur', () => {
    for (const key of Object.keys(keys) as (keyof typeof keys)[]) keys[key] = false;
  });

  const resize = () => stage.resize(window.innerWidth, window.innerHeight);
  window.addEventListener('resize', resize);
  window.addEventListener('orientationchange', resize);
  resize();

  // ---- loop --------------------------------------------------------------

  can.setBase(state.canX, state.canZ);
  hud.render(state);

  let last = performance.now();
  function frame(now: number): void {
    const dt = Math.min((now - last) / 1000, MAX_FRAME_STEP);
    last = now;

    if (!state.paused && (state.phase === 'aiming' || state.phase === 'intro')) {
      state = setAim(state, applyKeyboardAim(state.aim, keys, dt));
      state = tick(state, dt);
    }

    const sole = solePosition(state);
    const wobble = wobbleAt(state.clock, state.seed);

    if (animation) {
      animation.previous = animation.elapsed;
      animation.elapsed += dt;
      const impact = state.impact!;
      const shape = stompFrame(animation.elapsed, animation.previous, animation.hoverY, state.outcome);

      can.update(state.outcome, shape.crush);
      foot.setPose(
        impact.offsetX + state.canX,
        shape.footY,
        impact.offsetZ + state.canZ,
        impact.tiltX,
        impact.tiltZ,
      );
      foot.setSquash(shape.squash);

      if (shape.impact) {
        const strength = state.outcome.contact ? 0.35 + state.outcome.coverage * 0.65 : 0.3;
        effects.burst(
          impact.offsetX + state.canX,
          impact.offsetZ + state.canZ,
          strength,
          state.reducedMotion,
        );
        audio.play(state.outcome.contact ? 'crunch' : 'thud', strength);
      }
      if (shape.reveal && !revealed) {
        revealed = true;
        state = revealResult(state);
        if (state.result && state.result.score >= 90) audio.play('chime');
        persist();
        hud.render(state);
      }
      if (animation.elapsed >= STOMP_DURATION) animation = null;
    } else if (state.phase !== 'result') {
      foot.setPose(sole.x, CAN_HEIGHT + sole.hover, sole.z, wobble.tiltX, wobble.tiltZ);
      foot.setSquash(1);
    }

    // The reticle tracks the sole and brightens as the foot comes level, so
    // the rhythm of the wobble is readable without a "press now" prompt.
    const live = state.phase === 'aiming' || state.phase === 'intro';
    stage.reticle.visible = live && !animation;
    if (stage.reticle.visible) {
      stage.reticle.position.set(sole.x, 0.006, sole.z);
      const closeness = windowCloseness(state.clock, state.seed);
      stage.reticleMaterial.opacity = 0.4 + closeness * 0.5;
      stage.reticle.scale.setScalar(1 + closeness * 0.08);
    }

    // The target ring stays where the can started; the contact shadow follows
    // the can itself, including when a glancing hit skids it away.
    stage.targetRing.position.set(state.canX, 0.005, state.canZ);
    stage.canShadow.position.set(can.group.position.x, 0.004, can.group.position.z);

    const cameraX = stage.camera.position.x;
    const cameraY = stage.camera.position.y;
    effects.update(dt, stage.camera);
    stage.renderer.render(stage.scene, stage.camera);
    stage.camera.position.x = cameraX;
    stage.camera.position.y = cameraY;

    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);

  if (import.meta.env.DEV) {
    // A development-only seam so the end-to-end tests can drive real input at
    // exact moments. It is stripped from production builds.
    (window as unknown as Record<string, unknown>).__canCrusher = {
      getState: () => state,
      camera: stage.camera,
      can,
      wobbleAt,
      nextPerfectInstant,
    };
  }
}

try {
  boot();
} catch (error) {
  const box = document.getElementById('error');
  if (box) {
    box.textContent = `Can Crusher could not start: ${
      error instanceof Error ? error.message : String(error)
    }`;
    box.hidden = false;
  }
}
