# Project Wayfinder - UI & Menu Design

Status: draft, informs the "UI foundation" epic.
Companion to `project_wayfinder_gdd (1).md`.

## 1. Goals

The game is systems-dense: belief probabilities, doctrine programming, forensic logs.
The menus have one job above all others - make a complex game legible to a new player without dumbing it down.
Two decisions drive everything below: a **layout technology** (Clay) and a **teaching structure** (the four-phase loop as curriculum).

## 2. Layout technology: Clay

We use [Clay](https://github.com/nicbarker/clay) via its official Odin bindings, vendored at `game/clay-odin/`.

### Why Clay

- Immediate-mode, declarative flexbox-like layout in pure Odin - no retained widget tree to keep in sync with game state.
- Renderer-agnostic: Clay computes geometry and emits a flat list of render commands; we write one adapter to karl2d.
- It handles the hard parts we would otherwise hand-roll: nested flex, scroll containers, text wrapping, floating/z-ordered elements (tooltips, dropdowns, modals, the belief-breakdown popover), and pointer hit-testing.
- Arena-allocated with a fixed memory budget declared up front - fits Odin and karl2d's no-GC, immediate-mode style.

### What Clay does not give us

Clay is layout + hit-testing only, not a widget toolkit.
There is no built-in button, slider, dropdown, or text-input behavior or state.
Clay reports "the pointer is over element X and the mouse is down"; we build widget semantics on top.
This game needs sliders (belief priors), dropdowns (route intent), toggles (pattern rules), and map-brush tools, so a thin widget layer over Clay is required work - tracked in the UI-foundation epic.

### Integration shape (proven by the spike)

The spike (`game/ui.odin`, toggle `[U]`) confirms the fit on Apple Silicon.
karl2d already exposes every hook Clay needs:

| Clay need | karl2d call |
|---|---|
| Text measurement callback | `measure_text` |
| Rectangle | `draw_rect` |
| Border | `draw_rect_outline` |
| Text | `draw_text` |
| Image | `draw_texture_rect` |
| Scissor start / end (scroll clip) | `set_scissor_rect(rect)` / `set_scissor_rect(nil)` |

The renderer (`ui_render`) is ~40 lines.
UI is built and drawn in screen space with the camera off (`k2.set_camera(nil)`), the same context `draw_hud` already runs in.

### Known gotchas

- Clay `Color` is RGBA floats in 0..255; karl2d `Color` is `[4]u8`. Mapped in `clay_color`.
- The measure-text callback is `proc "c"` with no Odin context - we stash a package `context` in `ui_init` and restore it inside the callback.
- Element ids are passed through the `clay.UI(id)` overload, not a struct field.
- Text measurement must use the exact font/size the renderer draws with, or wrapping drifts.
- karl2d draws sharp rects; Clay's corner radii are approximated (ignored) for now. Rounded corners are a later renderer improvement.

### Alternatives considered

- `microui` (rxi): also C with Odin bindings, simpler, but row/column-manual layout with no real flex - it would fight the dense, responsive three-panel screens.
- Roll-our-own (today's `draw_hud`): does not scale to this menu complexity.

## 3. Teaching structure: the four-phase loop is the curriculum

The GDD's run loop (GDD §2) is also the tutorial.
Each phase teaches one verb, and the menus make the current phase and the single next action impossible to miss.

```
Map Room  ->  Prep Table  ->  Simulation  ->  Expedition Log
(observe)     (program)       (watch)         (understand)
   ^                                              |
   +----------------------------------------------+
```

### Principle 1 - the map is always center-stage; menus dock around it

The persistent world map is the one shared object across all four phases.
These are not four separate fullscreen screens - they are docked panels around a continuous map.
The region a player studied in the Map Room is the same one they program in Prep and replay in the Log, which keeps them oriented.

### Principle 2 - one consistent spatial grammar everywhere

The forensic log already defines the grammar (GDD §7.1): **left = timeline / navigation, center = map, right = inspector / detail.**
Reuse it in every phase:

| Phase | Left | Center | Right |
|---|---|---|---|
| Map Room | expedition history | world map | tile / region inspector |
| Prep Table | doctrine sections | map with waypoints / brushes | live belief preview |
| Simulation | day ticker | run playback | active triggers |
| Expedition Log | day timeline | map at selected day | thought-process breakdown |

The player learns one layout once and applies it four times.
This is also the strongest argument for Clay: one layout engine expressing one grammar across every screen.

### Principle 3 - one primary action per phase

A persistent phase breadcrumb (Map Room -> Prep -> Sim -> Log) plus a single prominent call to action per screen:

- Map Room: **Plan Expedition**
- Prep Table: **Launch Expedition**
- Simulation: **Skip to Analysis**
- Expedition Log: **Return to HQ** / **Save as Template**

Depth is always opt-in; the happy path is always obvious.

### Principle 4 - progressive disclosure gated by meta-progression

This is the most important onboarding lever.
Do not show belief tuning, professions, gear, funding, custom proximity matrices, and map brushes on run 1.

First runs expose the minimum: pick a route intent, pick a terrain preset (or "Recommended"), set a goal, Launch.
Advanced controls unlock as headquarters departments are built - which is exactly what the GDD already describes (GDD §10.3: the Cartography Board "provides tools to draw waypoints, visualize belief overlays").

So department progression doubles as UI onboarding, and it matches the GDD §11.3 build order: strip down, confirm the loop is fun, then layer in.
Complexity arrives only once the player has earned the context to understand it.

Rough unlock ladder (tune during implementation):

| Unlocked by | Adds to the UI |
|---|---|
| Start | Route intent, terrain preset, goal, Launch |
| First runs / basic HQ | Risk protocols, dynamic triggers, manual waypoints |
| Cartography Board | Belief overlay, tile preferences / depreferences, guidance lines |
| Scholar's Guild / Academy | Professions, gear loadout |
| Advanced Cartography | Belief tuning (priors, pattern rules), branching fallback routes |

### Principle 5 - diegetic Victorian framing as a mnemonic

Name the screens in-fiction: "The Map Room", "The Prep Table", "The Expedition Log", "Headquarters" with departments as rooms.
The theme makes the structure memorable.
The Expedition Log is where the menus do their real teaching - tile-probability breakdowns and decision traces ("chose A over B: expected cost 2.1 < 3.4") make the black box legible.

## 4. Onboarding

The first expedition is a curated, guided run.
The GDD already curates early discoveries (GDD §12.5), so the first world is authored, not purely random.

- Pre-fill a recommended doctrine so the player can launch without understanding every control.
- Walk through each phase once with contextual coach-marks.
- End on the Expedition Log showing "here is what your explorer believed, and why."

That teaches the entire loop in a single run.

## 5. Relationship to the backlog

This document informs, and is informed by, the GitHub issues:

- Foundation for all UI work: the **UI foundation** issue (Clay integration + karl2d renderer + panel grammar + widget layer).
- Four-phase state machine: #9.
- Three-panel log UI: #13.
- Tile probability breakdown: #14.
- Prep-phase doctrine UI: #25.
- HQ departments (drive the unlock ladder): #29.

The spike that de-risked the Clay decision lives at `game/ui.odin` and `game/clay-odin/`; it is a throwaway proof-of-concept, not the final framework.
