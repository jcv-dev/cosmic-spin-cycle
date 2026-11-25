# Screens — Cosmic Spin Cycle (M6)

The five player-facing screens that are **not** the HUD. Design source of truth:
`docs/UX_BIBLE.md` §12; the design system is `scripts/ui/UITheme.gd`; the flow owner is
`scripts/main/App.gd` (this workstream does not edit either file).

Screens are pure presentation: they never read gameplay state, they emit intent signals and
`App` decides. The measured rules from `docs/UX_RESEARCH.md` §9/§13 are applied here: a 12 px
type floor, a 2 px `funk_cyan` + 1 px `space_void` focus ring, `metal_1` panel borders, and a
≤ 250 ms cancellable transition budget. Every screen sets `theme = UITheme.theme()`, calls `UITheme.wire_audio(self)`
after building, gives keyboard/gamepad focus a visible state, and moves the focus on mouse
hover.

## Inventory

| Screen | Scene | Script | Size | Focus order | Signals |
|---|---|---|---|---|---|
| Title | `scenes/ui/TitleScreen.tscn` | `scripts/ui/TitleScreen.gd` | full rect | INICIAR TURNO (28 px) → TUTORIAL (20) → CALIBRACIÓN DE AUDIO (20) → OPCIONES (16) → SALIR (16) | `start_requested`, `tutorial_requested`, `options_requested`, `calibration_requested`, `quit_requested` |
| First run | `scenes/ui/FirstRunPrompt.tscn` | `scripts/ui/FirstRunPrompt.gd` | full rect + 640×280 plaque | HACER EL TUTORIAL (default) → EMPEZAR EL TURNO | `tutorial_selected`, `skip_selected`, `closed` |
| Pause | `scenes/ui/PauseOverlay.tscn` | `scripts/ui/PauseOverlay.gd` | full rect + 560×470 plaque | REANUDAR → REINICIAR → OPCIONES → MENÚ | `resume_requested`, `restart_requested`, `options_requested`, `menu_requested` |
| Options | `scenes/ui/OptionsScreen.tscn` | `scripts/ui/OptionsScreen.gd` | full rect + 780×540 plaque | MAESTRO → MÚSICA → EFECTOS → CALIBRAR AUDIO → PANTALLA COMPLETA → REDUCIR MOVIMIENTO → ESCALA DEL HUD → VIBRACIÓN → RESTABLECER → VOLVER | `closed`, `calibration_requested` |
| End | `scenes/ui/EndScreen.tscn` | `scripts/ui/EndScreen.gd` | full rect + 720×560 plaque | REPETIR (default) → MENÚ → NUEVA SEMILLA | `retry_requested`, `new_seed_requested`, `menu_requested` |

Every screen exposes `focus_first()`; `App` calls it after instancing. Options also exposes
`open(from_pause: bool)` and End exposes `setup(result: Dictionary)` (`App` calls it before
adding the node, which is supported). Pause and Options run with `PROCESS_MODE_ALWAYS`
because the tree is paused behind them.

## Visual rules that are asserted in tests

| Rule | Where it lives | Test |
|---|---|---|
| Focus = 2 px `funk_cyan` ring + 1 px `space_void` gap (10.9:1 on `space_deep`) | `_focus_ring()` in each screen; menu rows keep the §12.1 caret + underline on top of it | `test_*_carry_the_measured_ring`, `test_focused_row_draws_the_measured_ring` |
| No text below 12 px; captions 14 px; menu rows 20–28 px | `FONT_SMALL` / `FONT_LABEL` / per-row sizes | `test_no_text_below_the_type_floor` (all five suites) |
| Panels and toggles use `metal_1` borders, never `metal_0` (2.34:1 fails 3:1) | `_panel()` per screen | `test_panel_border_uses_metal_1` |
| Title hierarchy from presentation, not omission: one 28 px primary, two 20 px secondary, two dimmed 16 px tertiary rows | `MENU_SIZES` / `MENU_INKS` | `test_type_tiers_descend_from_primary_to_tertiary` |
| Options shows ≤ 5 rows per column (4 + 4) plus a 2-button footer, one linear focus order | two fixed columns + footer row | `test_no_column_shows_more_than_five_rows` |
| End: four primary stats first, ENTREGADAS and SEMILLA inline as a footnote; rank 96 px | `LEDGER_SLOTS` | `test_four_primary_stats_are_bigger_than_the_secondary_pair`, `test_secondary_stats_sit_inline_with_their_caption` |

Focus ring, verified at 1:1 on the title's first row: `funk_cyan` 2 px, then one
`space_void` pixel, then the row fill.

## Input behaviour

| Key | Title | First run | Pause | Options | End |
|---|---|---|---|---|---|
| ↑ / ↓ | move focus (wraps) | stay on the pair | move focus (wraps) | move focus (wraps) | — |
| ← / → | move focus | move focus | move focus | change the focused value (slider, toggle) | move focus between buttons |
| ENTER / Ⓐ | activate | activate | activate | toggle the focused row | activate |
| ESC | focus SALIR (never quits by accident) | emit `closed` | `App` resumes (ESC is owned by `App`) | emit `closed` | emit `menu_requested` |

First run persists the choice: `EMPEZAR EL TURNO` writes `Settings.mark_first_run_done()` from
the prompt itself (the bible requires the prompt never to nag again), and the tutorial's own
completion writes `tutorial_completed` + `first_run_done` through `App`.

No screen has a "press any key" gate and nothing auto-advances: the first frame of the title is
interactive with INICIAR TURNO already focused (`_ready` calls `focus_first()`), and the only
animation in any of these screens is the end screen's 240 ms rank scale-in, which any key or
pad button cancels immediately.

Options is the only screen that writes settings: it writes `Settings` and calls
`Settings.save_settings()` + `Settings.apply()` on every change (no Apply button).

## Settings keys used

`master_volume_db`, `music_volume_db`, `sfx_volume_db` (−30…+6 dB, step 1), `fullscreen`,
`reduce_motion`, `haptics`, `ui_scale` (1.0 / 1.25), `user_calibration_offset`
(read-only readout), `best_score`, `best_rank` (title plaque, hidden when `best_score <= 0`),
and `db_seed` is never touched by these screens. `reset_to_defaults()` is what RESTABLECER
calls.

## Screenshots

All captured at 1280×720 with `tools/screenshot.gd`:

```bash
godot --headless --path . --import
godot --path . -s tools/screenshot.gd --audio-driver Dummy --display-driver wayland \
  --rendering-method gl_compatibility -- \
  --scene=res://scenes/ui/TitleScreen.tscn --out=res://docs/media/menu_title.png --frames=20
```

The title is captured from `res://scenes/main/Main.tscn` instead (frames=40) so the real boot
flow fills `Settings`: the standalone harness boots autoloads late, and a screen that reads
`Settings` in `_ready` would otherwise show the "no record yet" state.

- `docs/media/menu_title.png` — captured from `res://scenes/main/Main.tscn` so the real boot
  flow, `Settings` and the menu ambience are in play. The MEJOR TURNO plaque only appears
  when `settings.cfg` already holds a run; the capture has one seeded.
- `docs/media/menu_first_run.png`, `menu_pause.png`, `menu_options.png`, `menu_end.png` —
  captured from their own scene at 1280×720. First run and pause show their dimmer over the
  void when instanced alone; in game they dim the title or the paused room. The end screen
  falls back to `@export var preview_result` demo data when `setup()` was not called, which
  is what makes its capture reproducible without playing a shift.

## Verified inside `App`

An ad-hoc probe (dev-only, not committed) instanced `res://scenes/main/Main.tscn` headlessly
and confirmed the integration contract end to end:

- boot → `current_screen == &"title"`, `TitleScreen` instanced, focus on `StartButton`;
- `_on_title_start()` on a fresh install → `FirstRunPrompt`, focus on `TutorialButton`,
  `tutorial_selected` → `current_screen == &"tutorial"`;
- `start_shift(false)` → `pause_game()` → `PauseOverlay`, focus on `ResumeButton`,
  `options_requested` → `OptionsScreen` over the paused tree, `closed` → `resume_game()`
  returns to `&"shift"`;
- `_show_end(result)` → `EndScreen` with the given rank/seed and focus on `RetryButton`.

## Notes and deviations

- `UITheme.slider()` declares a 220 px minimum width; the options two-column layout needs a
  350 px full-width track, so the row sets its own geometry and keeps `UITheme.slider()` for
  range/step and the shared grabber styling. Reported rather than edited (UITheme is frozen).
- Sliders have no focus stylebox in the engine theme, so a focused slider draws the
  `UITheme.draw_focus_bracket()` in a 2 px cyan frame — the same language as the rest of the
  focus system.
- The five owner title items are kept (the research proposed three); the hierarchy comes from
  size and ink instead, so nothing the owner asked for was removed.
- `CALIBRACIÓN DE AUDIO` is 19 characters, above the ≤ 14-character button guideline: it is the
  owner's wording, it fits the 512 px row at 20 px, and renaming it to `CALIBRAR AUDIO` would
  change the owner's copy. `HACER EL TUTORIAL` and `EMPEZAR EL TURNO` are fixed by the brief.
- The end screen adds a small `ESCALA  S A B C` ladder under the rank letter (the rank is
  otherwise unexplained) and a `PERFECTOS / BIEN / FALLOS` line under the ledger; both read
  from the `result` dictionary and are the only copy beyond §12.5.
- The title's mission chip (`OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00`) is the one addition
  to §12.1: the owner's complaint was that the goal was invisible, and the title is the first
  place it can be stated.
- `App` never calls `OptionsScreen.open(from_pause)`: it instances the screen and calls
  `focus_first()`. The screen therefore also derives "opened from pause" from
  `get_tree().paused`, so the caption is right either way. If `App` later calls `open()`, the
  flag wins.
- The title's diorama is a static composition built from `data/layout.json` and the shipped
  sprites (no `Diorama.tscn` exists yet); it instances only the machinery on the right half
  of the room so nothing is cut in half by the menu plate. When `Diorama.tscn` lands, that
  node should replace `TitleScreen._build_props()`.
