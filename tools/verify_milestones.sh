#!/usr/bin/env bash
# Full milestone gate. Run from the repo root: ./tools/verify_milestones.sh
#
# Prints one PASS/FAIL line per gate and exits non-zero if any gate fails.
# Optional gates (art pipeline, audio pipeline, 480 s sim) are skipped with a clear note
# until their deliverable lands, so this script is usable during the whole wave.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"
GDT_BIN="${GDT_BIN:-$ROOT/.work/venv/bin}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$ROOT/.work/xdg/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT/.work/xdg/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$ROOT/.work/xdg/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$ROOT/.work/home"

FAILED=0
run_gate() {
	local name="$1"
	shift
	echo "──────── $name"
	if "$@"; then
		echo "PASS  $name"
	else
		echo "FAIL  $name"
		FAILED=1
	fi
}

skip_gate() {
	echo "SKIP  $1 ($2)"
}

run_gate "godot import" "$GODOT" --headless --path . --import
run_gate "GUT unit + integration suite" "$GODOT" --headless --path . \
	-s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
run_gate "headless main-scene smoke" "$GODOT" --headless --path . --quit
run_gate "gdlint" env HOME="$ROOT/.work/home" "$GDT_BIN/gdlint" scripts tests tools
run_gate "gdformat --check" env HOME="$ROOT/.work/home" "$GDT_BIN/gdformat" --check scripts tests tools

if [[ -f tools/lint_sprites.py ]]; then
	run_gate "sprite contract lint" python3 tools/lint_sprites.py
else
	skip_gate "sprite contract lint" "tools/lint_sprites.py missing"
fi

if [[ -f tools/verify_audio.py ]]; then
	run_gate "audio contract verify" python3 tools/verify_audio.py
else
	skip_gate "audio contract verify" "tools/verify_audio.py missing"
fi

if [[ -f tools/sim_run.gd ]]; then
	run_gate "480 s spawn simulation" "$GODOT" --headless --path . -s tools/sim_run.gd -- --seed=1234
else
	skip_gate "480 s spawn simulation" "tools/sim_run.gd missing"
fi

if [[ -f tools/playtest_bot.gd ]]; then
	# End-to-end "player brain": the loop must be completable, not just unit-tested.
	run_gate "E2E playtest bot (45 s)" "$GODOT" --headless --path . -s tools/playtest_bot.gd \
		-- --frames=2700
else
	skip_gate "E2E playtest bot" "tools/playtest_bot.gd missing"
fi

if [[ -f scenes/dev/PlayerSandbox.tscn ]]; then
	run_gate "player sandbox screenshot" "$GODOT" --path . -s tools/screenshot.gd \
		--resolution 1280x720 --audio-driver Dummy --display-driver wayland \
		--rendering-method gl_compatibility -- \
		"--scene=res://scenes/dev/PlayerSandbox.tscn" "--out=res://.work/screens/verify_player.png"
else
	skip_gate "player sandbox screenshot" "scene missing"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
	echo "ALL GATES PASSED"
else
	echo "SOME GATES FAILED"
fi
exit "$FAILED"
