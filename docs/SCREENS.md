# Screens — Cosmic Spin Cycle (M6)

The five player-facing screens that are **not** the HUD. Design source of truth:
`docs/UX_BIBLE.md` §12; the design system is `scripts/ui/UITheme.gd`; the flow owner is
`scripts/main/App.gd` (this workstream does not edit either file).

Screens are pure presentation: they never read gameplay state, they emit intent signals and
`App` decides. Every screen sets `theme = UITheme.theme()`, calls `UITheme.wire_audio(self)`
after building, gives keyboard/gamepad focus a visible state, and moves the focus on mouse
hover.

## Inventory

| Screen | Scene | Script | Size | Focus order | Signals |
|---|---|---|---|---|---|
| Title | `scenes/ui/TitleScreen.tscn` | `scripts/ui/TitleScreen.gd` | full rect | INICIAR TURNO → TUTORIAL → CALIBRACIÓN DE AUDIO → OPCIONES → SALIR | `start_requested`, `tutorial_requested`, `options_requested`, `calibration_requested`, `quit_requested` |
| First run | `scenes/ui/FirstRunPrompt.tscn` | `scripts/ui/FirstRunPrompt.gd` | full rect + 640×280 plaque | HACER EL TUTORIAL (default) → EMPEZAR EL TURNO | `tutorial_selected`, `skip_selected`, `closed` |
| Pause | `scenes/ui/PauseOverlay.tscn` | `scripts/ui/PauseOverlay.gd` | full rect + 560×470 plaque | REANUDAR → REINICIAR → OPCIONES → MENÚ | `resume_requested`, `restart_requested`, `options_requested`, `menu_requested` |
| Options | `scenes/ui/OptionsScreen.tscn` | `scripts/ui/OptionsScreen.gd` | full rect + 780×540 plaque | MAESTRO → MÚSICA → EFECTOS → CALIBRAR AUDIO → PANTALLA COMPLETA → REDUCIR MOVIMIENTO → ESCALA DEL HUD → VIBRACIÓN → RESTABLECER → VOLVER | `closed`, `calibration_requested` |
| End | `scenes/ui/EndScreen.tscn` | `scripts/ui/EndScreen.gd` | full rect + 720×560 plaque | REPETIR (default) → MENÚ → NUEVA SEMILLA | `retry_requested`, `new_seed_requested`, `menu_requested` |

Every screen exposes `focus_first()`; `App` calls it after instancing. Options also exposes
`open(from_pause: bool)` and End exposes `setup(result: Dictionary)` (`App` calls it before
adding the node, which is supported). Pause and Options run with `PROCESS_MODE_ALWAYS`
because the tree is paused behind them.

## Input behaviour

| Key | Title | First run | Pause | Options | End |
|---|---|---|---|---|---|
| ↑ / ↓ | move focus | move focus | move focus | move focus (row order above) | — |
| ← / → | move focus | move focus | move focus | change the focused value (slider, toggle) | move focus between buttons |
| ENTER / Ⓐ | activate | activate | activate | toggle the focused row | activate |
| ESC | focus SALIR (never quits by accident) | emit `closed` | `App` resumes (ESC is owned by `App`) | emit `closed` | emit `menu_requested` |

Options is the only screen that writes settings: it writes `Settings` and calls
`Settings.save_settings()` + `Settings.apply()` on every change (no Apply button).

## Settings keys used

`master_volume_db`, `music_volume_db`, `sfx_volume_db` (−30…+6 dB, step 1), `fullscreen`,
`reduce_motion`, `haptics`, `ui_scale` (1.0 / 1.25), `user_calibration_offset`
(read-only readout), `best_score`, `best_rank` (title plaque, hidden when `best_score <= 0`),
and `db_seed` is never touched by these screens. `reset_to_defaults()` is what RESTABLECER
calls.

## Screenshots

All captured at 1280×720 with `tools/screenshot.gd` (see `docs/PROGRESS.md` for the command):

- `docs/media/menu_title.png` — captured from `res://scenes/main/Main.tscn` so the real boot
  flow, `Settings` and the menu ambience are in play. The MEJOR TURNO plaque only appears
  when `settings.cfg` already holds a run; the capture has one seeded.
- `docs/media/menu_first_run.png`, `menu_pause.png`, `menu_options.png`, `menu_end.png` —
  captured from their own scene at 1280×720. First run and pause show their dimmer over the
  void when instanced alone; in game they dim the title or the paused room. The end screen
  falls back to `@export var preview_result` demo data when `setup()` was not called, which
  is what makes its capture reproducible without playing a shift.

## Notes and deviations

- `UITheme.slider()` declares a 220 px minimum width; the options two-column layout needs a
  350 px full-width track, so the row sets its own geometry and keeps `UITheme.slider()` for
  range/step and the shared grabber styling. Reported rather than edited (UITheme is frozen).
- Sliders have no focus stylebox in the engine theme, so a focused slider draws the
  `UITheme.draw_focus_bracket()` in a 2 px cyan frame — the same language as the rest of the
  focus system.
- The end screen adds a small `ESCALA  S A B C` ladder under the rank letter (the rank is
  otherwise unexplained) and a `PERFECTOS / BIEN / FALLOS` line under the ledger; both read
  from the `result` dictionary and are the only copy beyond §12.5.
- The title's mission chip (`OBJETIVO · LAVA Y ENTREGA HASTA LAS 06:00`) is the one addition
  to §12.1: the owner's complaint was that the goal was invisible, and the title is the first
  place it can be stated.
- The title's diorama is a static composition built from `data/layout.json` and the shipped
  sprites (no `Diorama.tscn` exists yet); it instances only the machinery on the right half
  of the room so nothing is cut in half by the menu plate. When `Diorama.tscn` lands, that
  node should replace `TitleScreen._build_props()`.
