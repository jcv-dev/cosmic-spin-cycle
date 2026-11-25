# QA checklist — M0–M3

Automated gates live in `./tools/dev.sh check` and `./tools/verify_milestones.sh`.
This file is the **human** pass: things a test cannot feel.

## M1 — beat engine & calibration

- [ ] `scenes/dev/BeatLab.tscn` opens, keys 1–4 switch 105/118/130/142 and the click track
      follows without drift over 2 minutes.
- [ ] The debug overlay's Δt marker lands inside the ±65 ms band when tapping deliberately
      on the click; a deliberately late tap reads positive.
- [ ] Calibration wizard: 10 taps → median shown; Apply persists across a restart
      (`user://settings.cfg`); Reset returns to 0.
- [ ] A wrong calibration offset (±150 ms) is visibly compensated after re-running the wizard.
- [ ] Audio keeps playing when the game is paused? (M6) — for now, stopping the conductor
      stops the click.

## M2 — player & items

- [ ] Movement: 8 directions, no diagonal speed boost, stops in ~0.5 s, never sticks on walls.
- [ ] Grab: within ~64 px only; second item cannot be grabbed; held item sits 48 px ahead and
      follows the aim smoothly without jitter.
- [ ] Throw: 20 consecutive throws from different angles; none tunnels through walls, none
      gets stuck, none explodes the simulation (NaN).
- [ ] PERFECT throws visibly faster than GOOD/MISS.
- [ ] Moon off-beat curves; gas giant off-beat is short; rocky is stable; sock is skittish;
      galaxy core drags nearby socks while carried.
- [ ] Dash: ~120 px, stops on a wall, cannot be spammed.
- [ ] 40 bodies on screen: readable frame rate, no physics jitter, HUD physics ms shown.

## M3 — belts, phases, spawning

- [ ] Phase 1: only north belt, only red/blue solid, one item every ~3.5 s.
- [ ] Phase 2 (01:30): south belt activates, ringed + socks appear, interval ~2.4 s.
- [ ] Phase 3 (03:22): west belt activates, yellow/spotted appear, interval ~1.7 s.
- [ ] Phase 3 belt reversal: 4-beat warning (visual + audio), then direction flips every
      16 measures; items are carried back, not teleported.
- [ ] Phase 4 (05:15): random spawns stop, 12 heavies + 1 core arrive; all reachable.
- [ ] Shredder: a missed item is eaten, stability −8 %, `dropped` counter increments, no
      double-hit when the item is freed.
- [ ] Same seed → same spawn order and positions across two runs (debug seed).
- [ ] HUD clock 00:00 → 06:00 over 480 s; phase label/BPM update at the right times.

## Accessibility / presentation

- [ ] Washers and holograms use colour **and** glyph (M4).
- [ ] Reduce-motion disables camera shake (M6).
- [ ] Text legible at 1280×720 and 1920×1080 (canvas_items stretch).
- [ ] No shimmer on moving sprites (nearest filter, no sub-pixel scale).
