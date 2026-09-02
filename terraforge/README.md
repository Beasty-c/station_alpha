# TerraForge

Terrain design and earthworks concept simulation, as a native Godot 4 desktop
application.

Start with flat ground, sculpt a landform, lay a road and place a structure,
get transparent cut/fill, trucking, equipment, schedule and preliminary cost
figures, then watch the site build itself step by step in 3D.

> **Concept simulation — not for construction.**
> TerraForge produces *proposed* and *simulated* information only. Nothing it
> generates has been surveyed, staked in the field, inspected, tested,
> reviewed, sealed, permitted or approved. See
> [Scope and honesty](#scope-and-honesty).

---

## Requirements

| | |
|---|---|
| **Engine** | Godot **4.3.stable** (pinned). No C#/Mono build required — the standard build is enough. |
| **Language** | GDScript only. No GDExtension, no native compilation, no external packages. |
| **Platform** | Developed and verified on Linux x86-64. Windows and macOS export presets are included. |
| **Network** | None. Nothing is downloaded, uploaded or phoned home at any point. |
| **Renderer** | `gl_compatibility` (OpenGL 3.3 / ES 3.0), so it runs on integrated laptop graphics. |

Get Godot 4.3 from <https://godotengine.org/download/archive/4.3-stable/> or:

```bash
curl -fsSLO https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip
chmod +x Godot_v4.3-stable_linux.x86_64
sudo ln -sf "$PWD/Godot_v4.3-stable_linux.x86_64" /usr/local/bin/godot
godot --headless --version     # expect: 4.3.stable.official.…
```

There is nothing else to install. There is no package manager step.

---

## Run it

```bash
# from the repository root
godot --path terraforge                 # launch the application
godot --path terraforge --editor        # open the project in the Godot editor
```

The app opens directly onto a flat, editable 240 m × 240 m site. There is no
splash screen, launcher or setup wizard.

### Test

```bash
terraforge/tools/run_tests.sh           # 641 headless domain tests
terraforge/tools/run_tests.sh -v        # ...with every assertion listed
```

Equivalently:

```bash
godot --headless --path terraforge --import
godot --headless --path terraforge --script res://tests/run_tests.gd
```

Exit code 0 means everything passed.

The UI harness loads the real application scene into a real window, drives the
whole workflow with synthesised input, and saves screenshots:

```bash
terraforge/tools/run_ui_tests.sh 1600x900 /tmp/shots
```

On a headless machine it wraps itself in `Xvfb` automatically.

### Build

Install the export templates for 4.3.stable once
(`Editor ▸ Manage Export Templates`, or `godot --headless
--install-export-templates`), then:

```bash
godot --headless --path terraforge --export-release "Linux/X11"      build/linux/TerraForge.x86_64
godot --headless --path terraforge --export-release "Windows Desktop" build/windows/TerraForge.exe
godot --headless --path terraforge --export-release "macOS"          build/macos/TerraForge.zip
```

Presets exclude `tests/` and `tools/` from the shipped package. No preset
carries a signing identity — sign and notarise with your own certificates
before distributing.

---

## The workflow

1. **Open** — a new project is a flat surface at an assumed elevation of 0 in a
   clearly-labelled local engineering grid. It is not georeferenced and the app
   says so.
2. **Sculpt** — Raise, Lower, Smooth, Flatten with adjustable radius and
   strength. Orbit with the middle mouse button, pan with the right, zoom with
   the wheel. Undo/redo with `Ctrl+Z` / `Ctrl+Shift+Z`.
   *Or press **Generate sample site*** for a hill with a road spiralling to the
   summit and a tower on top — which then stays fully editable.
3. **Analyze build** — cut, fill, material balance, truckloads, disturbed area,
   slopes and road grades, with every formula, assumption and confidence
   reason on screen.
4. **Generate construction sequence** — 21 candidate steps, each with
   prerequisites, work zone, material flow, equipment, crew, duration and cost.
   Steps that do not apply are listed with the reason they were omitted.
5. **Construction Playback** — play, pause, step, scrub or click any step. The
   ground rises from original grade to the finished design while cumulative
   material, truckloads, time and cost track the timeline position.

### Keyboard

| Key | Action |
|---|---|
| `W A S D` / arrows | Pan |
| `Q` `E` | Orbit |
| `R` `F` | Zoom |
| `Home` | Frame the whole site |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo / redo |
| `Ctrl+S` | Save |
| `Space` | Play/pause the construction timeline |
| `Tab` | Move between controls (focus is always visible) |

**Reduced motion** (Design tab ▸ Accessibility) advances playback in discrete
step jumps instead of sliding continuously.

---

## Architecture

The terrain **model** owns the truth; the mesh is only a view of it.

```
terraforge/
  domain/        engine-light model: heightfield, units, brush, road, tower,
                 earthworks, assumptions, validation, operations, project
  construction/  step graph, sequence generator, schedule, playback state,
                 construction-surface builder
  persistence/   versioned JSON schema + migrations, CSV and HTML exporters
  terrain/       tiled mesh renderer, analytic ray picking, 3D overlays
  scenes/        application shell, camera rig
  ui/            theme, widgets, panels, HUD, transport
  tests/         headless domain suites + the UI harness
  tools/         run scripts
```

Nothing in `domain/` or `construction/` touches a scene node, a viewport or a
frame rate. They are plain `RefCounted` classes, which is why the same code can
be tested headlessly, run on a worker thread, and later be driven by a
different front end.

### Four decisions worth knowing

**The heightfield is canonical, not the mesh.** An explicit contiguous
`PackedFloat32Array` with an origin, spacing and node count, always in metres.
Rendering, picking and analysis all read it; none of them writes back. Any
rectangular node window can be read or written independently, which is what
makes tiled rendering, partial rebuilds — and, later, tiled raster surfaces or
a TIN backend — possible without changing the model.

**Volumes come from an exact integral, never from brush events.** Between four
grid nodes the surface is *defined* as bilinear, and the mean of a bilinear
patch over its cell is exactly the average of its four corners. So

```
net = Σ cells  mean(d₀₀,d₁₀,d₀₁,d₁₁) × cell_area,    d = proposed − existing
```

is exact for that surface definition. Cut and fill have to be separated, and a
cell whose corner deltas change sign contains a daylight line, so those cells —
and only those — are refined into a 4×4 sub-grid. The number refined is
reported so the error source is visible. Quantities are always recomputed from
the two surfaces; nothing is accumulated as the user drags.

**The document is an operation history.** Every meaningful edit is a command —
`CreateFlatTerrain`, `RaiseTerrain`, `SmoothRegion`, `AddRoadAlignment`,
`PlaceTower`, `ChangeEstimateAssumption` — and the state is *derived* by
replaying them. Undo and redo move a cursor through that list. Terrain
snapshots every 10 operations keep replay cheap, and a test asserts that
replaying with snapshots equals replaying without them at every cursor
position, so the shortcut can never change an answer.

Road corridors and structure pads are applied *on top of* the sculpted surface
rather than baked into it, so editing a road's width or grade limit re-derives
the design instead of destroying the ground underneath.

**Playback is a pure function of the schedule position.** The construction
surface is built from the three authoritative surfaces plus a five-component
progress vector (strip, cut, fill, form, tower). Fill rises as a front from the
low point, cut descends from the high point — lift placement and excavation as
they actually happen. Position is stored in *schedule hours*, not frames, so
scrubbing to a point and playing to it give bit-identical results at 15 fps or
240 fps.

### Performance

Terrain is 121 × 121 nodes at 2 m spacing (14 400 cells) drawn as 36 tiles of
20 × 20 cells. An edit reports the node window it touched; only the overlapping
tiles are marked dirty and they are rebuilt across frames under a 6 ms budget.
Picking is an analytic ray march against the heightfield — no collision body,
so nothing needs throttling and an edit is pickable immediately. Analysis runs
on `WorkerThreadPool` over cloned surfaces, debounced at 350 ms while editing,
with progress and cancellation; results return to the main thread via
`call_deferred`.

The grid size is a prototype default, not an architectural ceiling: storage,
rendering and analysis are all tile-aware and window-addressable.

---

## Files it writes

Everything is local and user-initiated. TerraForge makes no network calls.

| Output | Notes |
|---|---|
| `*.tfproj.json` | Versioned project (schema **1.1.0**). Terrain as base64 float32 so round trips are bit-exact, plus the full operation history, features, assumptions, analysis and sequence. Loader migrates 1.0.0 and refuses files claiming a professional data status. |
| `*_quantities.csv` | Earthwork quantities, units in every row, formulas as the basis column. |
| `*_estimate.csv` | Cost breakdown, low/expected/high, and every assumption with its source label. |
| `*_sequence.csv` | All steps: prerequisites, timing, material, loads, equipment, costs, omission reasons. |
| `*_equipment.csv` | Fleet with machine hours and the reason each class was selected. |
| `*_summary.html` | Print-friendly summary with a print stylesheet. No scripts, no external resources. |

CSVs are RFC 4180 with CRLF and a UTF-8 BOM, so Excel and LibreOffice open them
correctly, and each starts with a metadata block carrying the project status,
units, schema version and calculation-engine version.

`Design ▸ Local data ▸ Clear TerraForge's local project folder` deletes only
files the app saved to its own application-data folder; files you saved
elsewhere are untouched.

---

## Scope and honesty

**What TerraForge does not do.** Slope stability, soil bearing capacity,
settlement and groundwater are not analysed. Drainage appears as a cost
allowance only — there is no hydrologic or hydraulic design. Property
boundaries, easements and setbacks are not represented. No permit,
environmental or code compliance check is performed. Foundation sizing is a
volume placeholder for take-off, not a structural or geotechnical design.

**Costs are modelled, not quoted.** Every rate shipped with the app is an
illustrative placeholder, labelled as such in the interface and in every
export. They are not supplier quotes, not published indices and not local
market rates. Replace them with your own verified figures before the numbers
mean anything. Estimates always carry a date, an uncertainty band and a
confidence grade with its reasons.

**Stakes are proposals.** Stake positions shown in playback or listed in an
export are *proposed stakeout locations derived from the design model*. They
have not been set, checked or verified in the field, and the app never says
otherwise.

**Status cannot be escalated.** The model can express `field_measured` and
`professionally_certified` so a future module can use them honestly, but V1
only ever produces `proposed` and `simulated` — and the loader forces any file
claiming more back down to `simulated`. A test asserts that no export ever
contains an affirmative claim of certification, approval, survey, inspection,
permitting or construction-readiness.

---

## Known limitations

- **The existing surface is synthetic.** V1 starts from a flat assumed datum,
  not survey data. There is no import for real surfaces, point clouds, TINs or
  coordinate reference systems yet. The domain model is shaped to accept them;
  the adapters are not written.
- **Road alignments are edited numerically, not by dragging.** Control points
  come from `Add road` or `Generate sample site`; width, grade limit, shoulder
  and surfacing are then edited in the Design tab. There is no on-canvas
  vertex editing.
- **The tower is a massing placeholder.** A tapered mast on a pad, sized for
  quantity take-off. It is not a structural model.
- **The schedule is sequential.** Steps run back to back with no float,
  parallelism or calendar. It is a duration model, not a CPM programme.
- **Disturbed area is measured per cell.** A cell counts as disturbed if any
  corner moved more than 10 mm; partial cells are not sub-divided, so the
  figure is slightly conservative at the edges.
- **Grid resolution is fixed per project** at creation. Changing site
  dimensions after the fact is not exposed in the UI.
- **Verified on Linux only.** The Windows and macOS presets are standard and
  the project has no platform-specific code, but neither build has been run
  here. Both are unsigned.
- **Cut/fill split carries more uncertainty than the net.** The net volume is
  exact for the bilinear surface; the split depends on where the daylight line
  falls inside the refined cells. The analysis reports how many cells were
  refined so you can judge it.

---

## Testing

`tools/run_tests.sh` — **641 assertions**, no engine window required:

| Suite | Covers |
|---|---|
| Units | Exact ft / US-ft / CY factors, round trips, rejection of unknown units, the 1 000 000 ft vs US ft bust |
| Heightfield | Grid geometry, bilinear sampling, region windows, slope, bit-exact serialisation, brush kernels, degenerate inputs |
| Earthworks | Volumes against analytic surfaces — uniform lift, tilted plane, wedge, cone (⅓πr²h), square pyramid — with documented tolerances, plus determinism, grid-mismatch guards and subdivision convergence |
| Estimating | Material factors, truckload arithmetic, zero/negative truck capacity, production-rate and cost traceability, fleet planning, unit-display independence |
| Operations | History replay, undo/redo, snapshot equivalence, parametric features, redo-tail discard |
| Features | Alignment resampling, grade clamping, corridor grading, pad levelling, degenerate alignments |
| Construction | Step coverage, prerequisite ordering, schedule roll-up, omitted steps, surface endpoint exactness, frame-rate independence, empty sequences |
| Persistence | JSON round trips, malformed files, 1.0.0 migration, status-escalation refusal, CSV shape and quoting, report content |
| Validation | Every rule, actionability of every message, and that no export asserts a professional status |

`tools/run_ui_tests.sh` — **82 assertions** against the running application,
including synthesised pointer drags that sculpt through the real input path,
camera orbit that must not edit, mode guards, and keyboard reachability of
every visible control.

Verified at 1920×1080, 1600×900, 1440×900 and 1100×768.

---

## Next

Import a real survey surface. Everything else in this list is downstream of it:
the coordinate system, the datums, the confidence grade and half the
limitations above all exist because the existing ground is currently synthetic.
