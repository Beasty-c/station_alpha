/**
 * The DOM layer.
 *
 * It reads game state and writes text; it never computes anything about the
 * game itself.
 */

import type { GameState } from '../domain/game';

export interface HudHandlers {
  onRetry(): void;
  onToggleMute(): void;
  onTogglePause(): void;
  onToggleMotion(): void;
  onDismissIntro(): void;
}

function required<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing element #${id}`);
  return element as T;
}

export class Hud {
  private readonly best = required('best');
  private readonly attempts = required('attempts');
  private readonly hint = required('hint');
  private readonly intro = required('intro');
  private readonly result = required('result');
  private readonly paused = required('paused');
  private readonly score = required('score');
  private readonly label = required('label');
  private readonly reason = required('reason');
  private readonly errorBox = required('error');
  private readonly muteButton = required<HTMLButtonElement>('mute');
  private readonly pauseButton = required<HTMLButtonElement>('pause');
  private readonly motionButton = required<HTMLButtonElement>('motion');
  private readonly bars = {
    centering: required('bar-centering'),
    uprightness: required('bar-uprightness'),
    flatness: required('bar-flatness'),
    symmetry: required('bar-symmetry'),
  };

  constructor(handlers: HudHandlers) {
    required<HTMLButtonElement>('retry').addEventListener('click', handlers.onRetry);
    required<HTMLButtonElement>('resume').addEventListener('click', handlers.onTogglePause);
    required<HTMLButtonElement>('intro-start').addEventListener('click', handlers.onDismissIntro);
    this.muteButton.addEventListener('click', handlers.onToggleMute);
    this.pauseButton.addEventListener('click', handlers.onTogglePause);
    this.motionButton.addEventListener('click', handlers.onToggleMotion);
  }

  render(state: GameState): void {
    this.best.textContent = String(state.best);
    this.attempts.textContent = String(state.round);

    const showResult = state.phase === 'result' && state.result !== null;
    this.result.hidden = !showResult;
    this.intro.hidden = state.phase !== 'intro';
    this.paused.hidden = !state.paused;

    // The hint is for the first few rounds only; after that it fades away so
    // the play area stays clear.
    this.hint.dataset.quiet = String(showResult || state.paused || state.round > 3);

    this.muteButton.setAttribute('aria-pressed', String(state.muted));
    this.muteButton.lastElementChild!.textContent = state.muted ? 'Muted' : 'Sound';
    this.pauseButton.setAttribute('aria-pressed', String(state.paused));
    this.motionButton.setAttribute('aria-pressed', String(state.reducedMotion));
    this.motionButton.lastElementChild!.textContent = state.reducedMotion ? 'Calm' : 'Motion';

    if (!state.result) return;
    const { score, label, explanation, components } = state.result;
    this.score.textContent = String(score);
    this.label.textContent = label;
    this.reason.textContent = explanation;
    this.result.dataset.tier = score === 0 ? 'miss' : score >= 90 ? 'great' : 'normal';
    for (const [key, element] of Object.entries(this.bars)) {
      const value = components[key as keyof typeof components];
      element.style.width = `${Math.round(value * 100)}%`;
    }
  }

  /** Shows an unrecoverable problem in plain language instead of a blank screen. */
  showError(message: string): void {
    this.errorBox.textContent = message;
    this.errorBox.hidden = false;
  }
}
