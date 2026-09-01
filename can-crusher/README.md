# Can Crusher

A quick, low-poly arcade game: a wobbling foot hovers over an upright aluminium
can, and you have one stomp to flatten it as centrally and as straight as you
can. Every attempt is scored 0–100 on where the sole landed, how level it was,
and how flat and even the wreckage is. A round takes about five seconds.

It runs entirely in the browser. No account, no backend, no network calls after
the page has loaded, and nothing about your play leaves the tab.

```
npm install
npm run dev        # http://localhost:5173
```

## Commands

| Command | What it does |
| --- | --- |
| `npm install` | Installs dependencies (three.js, Vite, Vitest, TypeScript). |
| `npm run dev` | Development server with hot reload. |
| `npm test` | Runs the test suite once. |
| `npm run test:watch` | Runs the tests in watch mode. |
| `npm run typecheck` | Type-checks without emitting. |
| `npm run build` | Type-checks, then builds to `dist/`. |
| `npm run preview` | Serves the built `dist/` for a final check. |

Requires Node 20 or newer. The build output in `dist/` is a handful of static
files with relative paths: serve it from any static host and it works with no
backend and no network requests. (It needs a server rather than a bare
`file://` open, because browsers block ES modules loaded from the filesystem.)

## How to play

1. **Aim.** Move the mouse, drag a finger, or hold the arrow keys / WASD. The
   ring on the concrete is where the sole is right now — not where your cursor
   is, because the foot drifts.
2. **Watch the wobble.** The foot drifts sideways, rolls from edge to edge, and
   bobs up and down on a 2.4 second cycle. Twice per cycle it passes through
   dead level at the top of its bob. That is the moment worth waiting for.
3. **Stomp.** Click, tap, or press <kbd>Space</kbd> / <kbd>Enter</kbd>.

Other keys: <kbd>M</kbd> mute, <kbd>P</kbd> or <kbd>Esc</kbd> pause,
<kbd>R</kbd> retry from the score card.

## How the score works

The score comes out of the same numbers that shape the can, so the number
always matches the wreckage on screen. Four things are measured:

| Component | Weight | What it measures |
| --- | --- | --- |
| Centred | 30% | Distance from the sole centre to the can's axis. |
| Level | 18% | Total foot tilt at the moment of impact. |
| Flat | 32% | Final can height, from the deformation model. |
| Even | 20% | How symmetrical the crush is, versus folded to one side. |

The weighted total is raised to a small power (so a merely good stomp is not a
100) and multiplied by how solid the contact was (so clipping the rim with a
perfectly level foot cannot bank full marks for being level).

- **0** is reserved for a genuine miss — the sole never touched the can, and the
  can is left exactly as it was. Any contact at all scores at least 1.
- **100** needs the sole within 0.03 world units of the axis (about 9% of the
  can's radius) and the foot within 1.7° of level. That dead zone exists so a
  human can actually reach 100; outside it the score falls away immediately.
- A representative slice of the curve, at full power:

  | offset ↓ / tilt → | 0.00 | 0.08 | 0.15 | 0.25 | 0.40 |
  | --- | --- | --- | --- | --- | --- |
  | 0.00 | 100 | 93 | 84 | 71 | 53 |
  | 0.10 | 90 | 83 | 75 | 63 | 45 |
  | 0.25 | 48 | 43 | 37 | 29 | 17 |
  | 0.50 | 22 | 19 | 15 | 10 | 3 |
  | 0.75 | 0 | 0 | 0 | 0 | 0 |

Labels are `Perfect Crush` (90+), `Clean Stomp` (60–89), `Bent It` (30–59),
`Glancing Blow` (1–29) and `Miss` (0), each with a one-line explanation of what
went wrong — "A shade to the right", "Centred, but the foot came down angled".

### Is it fair?

The wobble is strictly periodic and its phase is the only thing the round seed
changes. By construction the roll and the pitch share their zeros, and the bob
peaks at those same instants, so **every round contains a moment when the foot
is exactly level at full power** — twice per 2.4 s cycle. There is a test that
asserts this for a range of seeds, and another that plays a round through the
real game state machine and requires a 100. Randomness moves the can a little
and shifts the phase; it never moves the ceiling.

## Architecture

```
src/
  domain/      pure game logic — no DOM, no three.js, no timers
    constants.ts   the play field's dimensions and tolerances
    math.ts        clamping, easing, the seeded hash
    types.ts       Impact, CrushOutcome, ScoreBreakdown
    crush.ts       impact  → the shape of the crushed can
    scoring.ts     outcome → 0–100, a label and an explanation
    canShape.ts    outcome → where every vertex of the can goes
    wobble.ts      the foot's periodic drift, tilt and bob
    input.ts       pointer/keyboard normalization and clamping
    game.ts        the round state machine
  render/      three.js: scene, can mesh, foot, effects, timeline, picking
  ui/          the DOM overlay and its stylesheet
  audio.ts     procedurally synthesised sound (no audio files)
  storage.ts   sessionStorage adapter for the best score and preferences
  main.ts      wiring: input → state → scene
```

The split is the point: `domain/` decides everything and can be tested in Node,
`render/` only draws. `crush.ts` produces one `CrushOutcome`, and both the score
and the mesh are derived from it — the deformation is not decoration over a
separate scoring formula.

**Choices.** three.js for rendering because it is the mature, well-supported
option for WebGL and the scene is small enough that its size is the only cost.
Vite and Vitest for a fast, conventional build and test loop. TypeScript in
strict mode. No framework for the interface: the HUD is a dozen elements, and a
framework would be more machinery than the job needs. All geometry, colour and
sound is generated in code, so the repository carries no art assets and nothing
proprietary.

## Tests

`npm test` runs 91 tests across eight files, all of them about behaviour rather
than rendering:

- **scoring** — perfect stomps score exactly 100, misses exactly 0, every result
  is an integer in range, the score falls monotonically as the offset or the
  tilt grows, contact never scores 0, labels band correctly, explanations name
  the right side, and `NaN`/`Infinity`/absurd inputs are handled rather than
  propagated.
- **crush geometry** — lid coverage, contact detection at and past the rim.
- **canShape** — a flawless stomp flattens the can to the model minimum and
  leaves it symmetrical; a glancing one folds it away from the pressed side and
  skids it; a miss leaves every vertex untouched at every animation step; no
  vertex ever goes below the slab or becomes `NaN`.
- **wobble** — periodicity, amplitude envelope, and the fairness guarantee above.
- **input** — pointer-to-NDC mapping, degenerate rects, diagonal speed, the
  frame-time cap, key mapping.
- **pick** — the aim lands under the pointer and stays on the reachable slab.
- **game** — phase transitions, the clock freezing during a stomp, double-stomp
  rejection, and that a retry resets the can, the aim, the clock, the impact and
  the result while keeping the session best and the player's preferences.
- **timeline** — the stomp animation is continuous, fires its impact exactly
  once, rides the can down, and clamps outside its own duration.
- **can mesh** — the can stays on its mark through a clean crush and only skids
  off it when the stomp was lopsided, and it rebuilds pristine and upright.

## What was checked by hand

Driven in headless Chromium at 320×640, 390×844, 820×1180, 844×390, 1280×800
and 1440×900: no page overflow at any size, no console errors, mouse, keyboard
and touch all play a full round, touch never scrolls or zooms the page, the
score card never covers the crushed can, `prefers-reduced-motion` is picked up
automatically, the game plays muted, pause freezes the wobble and refuses a
stomp, retry resets the scene, and the session best survives a reload. A scripted
run through the real input path reaches exactly 100 for a flawless stomp and
exactly 0 for a miss, with edge strikes landing in the low twenties and clips
right on the rim around ten.

## Known limitations

- **Frame rate was not measured on real GPU hardware.** The verification
  environment only has a software rasteriser, which manages about 17 fps and
  says nothing useful about a real device. What can be said: the scene is under
  two thousand triangles with a single 1024² shadow map (512² on low-power
  devices), the per-frame JavaScript is allocation-free, and the heaviest piece
  of work — rebuilding all 437 can vertices — costs 0.11 ms and only runs during
  the 0.24 s crush. There is nothing in the frame that should trouble a modern
  phone, but that is an inference, not a measurement.
- **The bundle is 141 kB gzipped**, nearly all of it three.js. That is one
  request on a warm connection and it is cached afterwards, but a hand-written
  WebGL renderer would be a fraction of the size.
- **The deformation is procedural, not a physics simulation.** It is
  deterministic and every visible feature — height, fold, tip, skid, bulge —
  comes from the impact and feeds the score, but no rigid bodies or material
  models are involved. Cans stepped on in real life buckle in more interesting
  ways.
- **Sound is synthesised at runtime** from noise and oscillators. It is
  serviceable rather than good, and it stays silent until the first real gesture
  because browsers require that.
- **The best score is per-tab**, in `sessionStorage`. Closing the tab clears it.
  That is deliberate: nothing about a player is worth keeping longer.
- **No device-motion controls.** Mouse, touch and keyboard only.
