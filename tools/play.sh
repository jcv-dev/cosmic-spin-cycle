#!/usr/bin/env bash
# Launch the game for a human playtest at the exact 1280x720 art viewport.
#
# On Wayland, Godot may default to the X11 driver and fail with "X11 Display is not
# available" even when a compositor is running; when WAYLAND_DISPLAY is set we ask for the
# Wayland driver explicitly. XDG user dirs are left alone, so settings persist in the
# player's real profile (delete them to replay the first-run prompt).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-godot}"
args=(--path . --resolution 1280x720)
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
	args+=(--display-driver wayland)
fi
exec "$GODOT" "${args[@]}"
