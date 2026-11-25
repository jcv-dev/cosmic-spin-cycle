# M3 — Belts, spawning and phases

Branch `m3-world`. Scope: `ConveyorBelt`, `Shredder`, `SpawnDirector`, `SpawnSchedule`,
`BeltReversal`, the phase data, `WorldSandbox` and `tools/sim_run.gd`. M2 is not required:
the spawner and every test run without `LaundryItem`.

## Data — `data/phases.tres`

`PhaseTable` (`scripts/data/PhaseTable.gd`) holds four `PhaseData` resources
(`scripts/data/PhaseData.gd`). `validate()` asserts continuity (no gaps, no overlaps,
increasing windows), a positive BPM, a positive spawn interval for timed phases, at least
one belt, colour, pattern and item weight, and a convoy composition whose heavies + core
match `convoy_count` with the last slot before the phase end.

| # | window | BPM | interval | belts | colours | patterns | items (weight) |
|---|---|---|---|---|---|---|---|
| 1 | 0–120 s | 105 | 3.5 s | north | red, blue | solid | rocky 5, sock 3, moon 2 |
| 2 | 120–270 s | 118 | 2.4 s | north, south | red, blue | solid, ringed | rocky 4, sock 4, moon 2, gas 1 |
| 3 | 270–420 s | 130 | 1.7 s | north, south, west | + yellow | + spotted | rocky 3, sock 3, moon 3, gas 2 |
| 4 | 420–480 s | 142 | convoy | all | all | all | 4 gas + 4 moon + 4 rocky + core |

Convoy: 13 slots every 4.5 s (420.0 … 474.0), heavies in composition order, the galaxy core
in the last slot. The core carries no colour/pattern (`&""`), because it is the wildcard.
`tests/unit/test_phase_*.gd` compares the resource against `Config`, `data/layout.json` and
`Config.FINAL_LOAD_*` rather than restating numbers; the belt activation per phase is read
from `layout.json`'s `active_phases`.

## Spawn schedule — `scripts/logic/SpawnSchedule.gd`

Pure and static. `build(phase_table, seed) -> Array[Dictionary]` returns
`{time, item_id, color, pattern, phase}` sorted by time and owns a private
`RandomNumberGenerator`; the global RNG is untouched. Interval phases spawn at
`start_s + interval * n` while `n >= 1` and the time stays inside the phase, which lands the
shipped counts on exactly **34 / 62 / 88 / 13 = 197**. Item weights are accumulated in
sorted-id order, so reordering the dictionary cannot change a seed's output. Convoys walk
the authored slots. `counts_by_phase()` and `summarize()` feed the tools and tests.

## Director — `scripts/components/SpawnDirector.gd`

`start(seed)`, `stop()`, `advance_to(t)` (idempotent, never runs backwards), `seek(t)` (move
without replaying skipped phases), `force_phase(index)`, `alive_count()`,
`spawned_count_by_phase`, `simulate(duration, seed)`.

Items are tagged with `item_id`/`color`/`pattern` metadata and `setup()` is called when the
scene provides it, then parented under `Items` (or `items_parent_path`), added to the
`items` group and announced with `item_spawned`. `Config.MAX_ALIVE_ITEMS` is enforced; the
overflow is counted in `skipped_count` instead of being queued. Phase changes activate the
belts of that phase by `belt_id`.

`item_scene` falls back to `Config.SCENE_LAUNDRY_ITEM` when that scene exists. Before M2 it
is null, and two escape hatches keep M3 testable: `stub_factory` (a `Callable(event) -> Node`)
and accounting mode (no factory, no tree) where events are counted but nothing is
instantiated. `position_resolver` lets the sandbox place each item on the belt that is
running. When M2 lands, drop `SCENE_LAUNDRY_ITEM` in and `setup()` does the rest.

## Belts — `scripts/environment/ConveyorBelt.gd`

`Area2D` layer 8, mask 4, `monitorable = false`, `CollisionShape2D` child. Every physics
tick each non-held `RigidBody2D` overlap is steered toward
`flow * belt_speed * item.belt_speed_scale` by `BELT_ACCEL * delta` (never assigned, D006);
`steer_velocity()` is a static pure function so the rule is unit-testable without physics.
The speed scale resolves `ItemData.belt_speed_scale`, then `belt_speed_scale` metadata
(greybox stubs), then the sock 1.6× rule. `active` gates everything; `set_flow_direction()`
snaps to the dominant axis; `configure(id, art_rect, flow)` places it from `layout.json`.

The visual is procedural and palette-locked through the new
`scripts/environment/EnvironmentPalette.gd` (reads `art/palette.json`, magenta on a typo):
metal deck, rails and chevrons scrolling along the flow, cyan while running, `space_haze`
when off, `hazard_orange` while a reversal is announced.

## Reversal — `scripts/logic/BeltReversal.gd`

Pure. Active only in zero-based phase 2 (the GDD's phase 3). Flips every 16 measures
(64 beats) and warns 4 beats before. `on_beat(beat, measure, phase)` returns
`{warn, flip, beats_left}`; a beat is consumed once, and `is_reversed` alternates. Measured
at 130 BPM (phase 3): **warnings on beats 60 / 124 / 188, flips on 64 / 128 / 192**, i.e.
every ~29.54 s, with nothing outside phase 3.

## Shredder — `scripts/environment/Shredder.gd`

`Area2D` layer 16, mask 4. `consume(body)` emits `fell_off_belt` on the item, applies
`Config.STABILITY_FELL_OFF_BELT` (−8) with reason `"shredder"`, bumps
`GameState.dropped_count`, reports `item_consumed` and frees the body. Entry is guarded by
instance id, because an item already queued for deletion can report a second overlap.
The vortex is procedural (rotating hazard/metal arcs).

## Sandbox and tools

`scenes/dev/WorldSandbox.tscn|gd` builds the floor, walls, three belts and three shredders
from `data/layout.json` (art px × `ART_SCALE`), spawns palette-disc stub items through the
director and runs its own deterministic shift clock, so it works with no beat stack and no
M2. Readout: clock, phase, BPM, beat/measure, per-phase spawns, alive, dropped, seed.
Keys **1–4** force a phase (via `seek`, so skipped phases are not replayed), **R** restarts
with a new seed, and the shift loops at 480 s.

```bash
godot --headless --path . -s tools/sim_run.gd -- --seed=1234
# sim_run seed=1234 total=197 per_phase=[34, 62, 88, 13] first=3.50s last=474.00s elapsed=1.60ms
# P1 0-120s 105BPM 3.50s spawned=34 | P2 120-270s 118BPM 2.40s spawned=62
# | P3 270-420s 130BPM 1.70s spawned=88 | P4 420-480s 142BPM convoy spawned=13
# plus the full JSON report (phase windows, by_item, the 13 convoy slots with times)
```

## Verification

| Gate | Result |
|---|---|
| `godot --headless --path . --import` | exit 0 |
| GUT (`tests`, incl. `tests/integration`) | 174 / 174 passing, 1.4 s |
| `gdlint scripts tests tools` | exit 0 |
| `gdformat --check scripts tests tools` | exit 0 |
| `tools/sim_run.gd -- --seed=1234` | exit 0, 197 spawns, 1.6 ms |
| `godot --headless --path . --quit` | exit 0 |
| virtual 480 s counts | 34 / 62 / 88 / 13, total 197 (±2) |
| reversal at 130 BPM | warnings 60/124/188, flips 64/128/192 |

`gdlint`/`gdformat` also pass on `scenes/dev` (the sandbox script lives there per the
ownership map, outside the three lint roots, so it was checked explicitly).

## Decisions for the lead to copy into `docs/DECISIONS.md`

1. **Spawn convention**: timed phases spawn at `start_s + interval * n`, `n >= 1`, strictly
   inside the phase. This is what yields 34/62/88 + 13 = 197; spawning at `start_s` would
   give 200 and break the acceptance number.
2. **Convoy timing**: 13 slots every 4.5 s from 420 s, core in the last slot (474 s).
   Composition order is gas, moon, rocky. Flip `convoy_interval_s`/`convoy_core_slot` in
   `data/phases.tres` to retune; `PhaseTable.validate()` guards the invariants.
3. **Variant-less core**: `color`/`pattern` are `&""` for `galaxy_core`; consumers must treat
   an empty variant as "wildcard", not as a missing value.
4. **Alive cap semantics**: events dropped by `MAX_ALIVE_ITEMS` are *not* counted in
   `spawned_count_by_phase`; they show up in `skipped_count`. Acceptance counts are therefore
   measured on the schedule/accounting path, not on a capped live run.
5. **Belt speed scale resolution order**: `ItemData.belt_speed_scale` → `belt_speed_scale`
   metadata → sock rule (`Config.BELT_SOCK_SPEED_SCALE`) → 1.0.
6. **Sandbox clock**: the dev scene keeps its own beat grid instead of reading
   `BeatConductor`, so it runs headlessly and cannot drift with audio calibration. MainLevel
   should forward real `BeatConductor.beat_hit`/`measure_hit` into `ConveyorBelt.on_beat`.
7. **Reverse direction restore**: belts return to their `layout.json` flow when a phase
   change leaves phase 3; the reversal counter resets on every phase change.

## Known issues

- Godot prints `N ObjectDB instances were leaked at exit` after some GUT runs (the leak list
  is `GDScript`/`RefCounted`/`PackedScene`/`Theme` resources, no game nodes). Exit code stays
  0 and GUT reports all tests passing; it reproduces with `-gselect=spawn_director` or
  `-gselect=world_sandbox` on an otherwise green file and not on the full unit directory, so
  it looks like GUT 9.6.1 script-cache shutdown ordering on 4.7.2 rather than an M3 leak.
  Worth a second look when the addon is upgraded.
- M2 integration pending: `LaundryItem`'s `setup()`/`fell_off_belt` are consumed by duck
  typing, so the first run with the real item scene should be re-checked for the exact
  `belt_speed_scale` values in `data/items.tres`.
- The belt and grinder visuals are greybox primitives in palette colours; they are replaced
  by `env_belt`/`env_shredder` in M7, not extended.
