#!/usr/bin/env bash
# Developer entry point for Cosmic Spin Cycle (Linux/macOS).
#
#   ./tools/dev.sh check      # import + tests + lint + format check (default)
#   ./tools/dev.sh test       # headless GUT suite
#   ./tools/dev.sh lint       # gdlint
#   ./tools/dev.sh fmt        # gdformat --check
#   ./tools/dev.sh fix        # gdformat in place
#   ./tools/dev.sh run        # play the game
#   ./tools/dev.sh import     # rebuild the import cache
#   ./tools/dev.sh sim        # headless 480 s spawn simulation
#   ./tools/dev.sh shot NAME  # screenshot a scene (default Main.tscn)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"
GDT_BIN="${GDT_BIN:-$ROOT/.work/venv/bin}"
if [[ ! -x "$GDT_BIN/gdlint" ]]; then
	GDT_BIN="$(dirname "$(command -v gdlint || true)")"
fi

export XDG_DATA_HOME="${XDG_DATA_HOME:-$ROOT/.work/xdg/data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT/.work/xdg/cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$ROOT/.work/xdg/config}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$ROOT/.work/home"

GUT_ARGS=(
	--headless --path . -s addons/gut/gut_cmdln.gd
	-gdir=res://tests -ginclude_subdirs -gexit
)

cmd="${1:-check}"
case "$cmd" in
import)
	"$GODOT" --headless --path . --import
	;;
test)
	"$GODOT" "${GUT_ARGS[@]}"
	;;
lint)
	HOME="$ROOT/.work/home" "$GDT_BIN/gdlint" scripts tests tools
	;;
fmt)
	HOME="$ROOT/.work/home" "$GDT_BIN/gdformat" --check scripts tests tools
	;;
fix)
	HOME="$ROOT/.work/home" "$GDT_BIN/gdformat" scripts tests tools
	;;
check)
	"$GODOT" --headless --path . --import >/dev/null
	"$GODOT" "${GUT_ARGS[@]}"
	HOME="$ROOT/.work/home" "$GDT_BIN/gdlint" scripts tests tools
	HOME="$ROOT/.work/home" "$GDT_BIN/gdformat" --check scripts tests tools
	;;
run)
	"$GODOT" --path .
	;;
sim)
	"$GODOT" --headless --path . -s tools/sim_run.gd -- --seed="${2:-1234}"
	;;
shot)
	scene="${2:-res://scenes/main/Main.tscn}"
	out="${3:-res://.work/screens/shot.png}"
	"$GODOT" --path . -s tools/screenshot.gd --resolution 1280x720 \
		--audio-driver Dummy --display-driver wayland \
		--rendering-method gl_compatibility -- \
		"--scene=$scene" "--out=$out"
	;;
*)
	echo "unknown command: $cmd" >&2
	echo "usage: $0 [check|test|lint|fmt|fix|import|run|sim|shot]" >&2
	exit 2
	;;
esac
