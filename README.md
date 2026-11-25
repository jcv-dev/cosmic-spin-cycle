# Cosmic Spin Cycle

*Lavandería al Borde del Vacío* — a 2D pixel-art rhythm-arcade game for PC (Windows + Linux).

You are Pip, the night-shift interdimensional janitor of an orbital laundromat. Catch dirty
celestial laundry off the conveyor belts, read its colour and pattern, and hurl it into the
right black-hole washing machine **on the beat** before the doors open at 06:00.

- **Engine:** Godot 4.7 (GDScript, static typing)
- **Design source of truth:** [`docs/GDD.pdf`](docs/GDD.pdf) (Spanish, Juan Camilo Valencia)
- **Executable engineering plan:** [`AGENTS.md`](AGENTS.md)
- **Frozen team contracts:** [`docs/CONTRACTS.md`](docs/CONTRACTS.md)
- **Decisions log:** [`docs/DECISIONS.md`](docs/DECISIONS.md)
- **Progress:** [`docs/PROGRESS.md`](docs/PROGRESS.md)

## Run

```bash
godot --path .              # open / play
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

On a headless CI box, point Godot's user dirs at a writable path:

```bash
export XDG_DATA_HOME="$PWD/.work/xdg/data" XDG_CACHE_HOME="$PWD/.work/xdg/cache" XDG_CONFIG_HOME="$PWD/.work/xdg/config"
```

## Status

Milestones **M0–M3** (bootstrap, beat engine + calibration, player/item physics, belts +
spawning + phases). See [`docs/PROGRESS.md`](docs/PROGRESS.md).

## Assets and licensing

All shipped artwork, music, SFX and fonts are public-domain / CC0 or openly licensed and
credited in [`docs/PROVENANCE.md`](docs/PROVENANCE.md). Source code is MIT (see
[`LICENSE`](LICENSE)). This is a university project; the game contains no ads, IAP,
telemetry or violence.
