/**
 * Session-scoped preferences.
 *
 * The game keeps the best score and the two toggles for as long as the tab is
 * open and no longer. Nothing is sent anywhere, and `sessionStorage` can throw
 * in a locked-down browser, so every access is guarded.
 */

const KEY = 'can-crusher/session';

export interface SavedSession {
  best: number;
  muted: boolean;
  tutorialDone: boolean;
}

const EMPTY: SavedSession = { best: 0, muted: false, tutorialDone: false };

export function loadSession(): SavedSession {
  try {
    const raw = window.sessionStorage.getItem(KEY);
    if (!raw) return { ...EMPTY };
    const parsed = JSON.parse(raw) as Partial<SavedSession>;
    const best = Number(parsed.best);
    return {
      best: Number.isFinite(best) ? Math.max(0, Math.min(100, Math.round(best))) : 0,
      muted: parsed.muted === true,
      tutorialDone: parsed.tutorialDone === true,
    };
  } catch {
    return { ...EMPTY };
  }
}

export function saveSession(session: SavedSession): void {
  try {
    window.sessionStorage.setItem(KEY, JSON.stringify(session));
  } catch {
    // Private browsing, disabled storage: the game just forgets between reloads.
  }
}
