extends Node
## Project-wide constants and pure helpers.
##
## Every number that comes from the GDD (or an explicit §A6 default) lives here or in a
## `data/*.tres` resource. Scripts must never hard-code balance values.

enum TransitionMode { HARD_CUT, DRUM_BRIDGE }

enum CollisionLayer {
	WORLD = 1,
	PLAYER = 2,
	ITEMS = 4,
	BELT = 8,
	SHREDDER = 16,
	CHUTE = 32,
	WASHER = 64,
}

# --- Shift & clock (GDD §2.2, §2.5) -----------------------------------------
const SHIFT_DURATION_S := 480.0
const GAME_HOURS := 6.0
const SECONDS_PER_GAME_HOUR := 80.0
const PHASE_START_S: Array[float] = [0.0, 120.0, 270.0, 420.0]
const PHASE_BPM: Array[int] = [105, 118, 130, 142]
## Retuned after the E2E bot proved the old 3.5/2.4/1.7 s cadence was 1.5x faster than one
## player can physically process (13 s loop). 10/8/6 s keeps pressure without being unwinnable.
const PHASE_SPAWN_INTERVAL_S: Array[float] = [6.0, 5.0, 4.0, 0.0]
const FINAL_LOAD_START_S := 420.0
const FINAL_LOAD_HEAVY_COUNT := 12
const FINAL_LOAD_CORE_COUNT := 1

# --- Player (GDD §3.2, §4.1) ------------------------------------------------
const PLAYER_ACCEL := 2400.0
const PLAYER_MAX_SPEED := 340.0
const PLAYER_FRICTION := 0.12
const HOLD_DISTANCE := 48.0
const GRAB_RADIUS := 64.0
const DASH_DISTANCE := 120.0
const DASH_DURATION_S := 0.18
const STRIKE_RANGE_PX := 96.0

# --- Rhythm (GDD §5.1) ------------------------------------------------------
## Windows widened after playtest #3: +-65/130 ms was only perceptible for players with
## rhythm-game experience. +-90/170 ms keeps the beat meaningful without becoming automatic.
const WINDOW_PERFECT_S := 0.090
const WINDOW_GOOD_S := 0.170
const PERFECT_FORCE_BONUS := 0.40
const BEATS_PER_MEASURE := 4
const COMBO_GAIN := {"PERFECT": 2, "GOOD": 1, "MISS": 0}
const COMBO_MIN := 1
const COMBO_MAX := 8
const WASH_REDUCTION_S := {"PERFECT": 3.0, "GOOD": 1.0, "MISS": 0.0}
const MISS_TURBULENCE_GAIN := 0.15
const WINDOW_SCALE_BY_PHASE: Array[float] = [1.0, 1.0, 1.0, 1.0]

# --- Washers (GDD §5.2) -----------------------------------------------------
const WASHER_COUNT := 4
const WASHER_CAPACITY := 3
const WASH_BASE_S := 8.0
const MIN_WASH_TIME_S := 2.0
const TURBULENCE_AT_PROGRESS := 0.50
const TURBULENCE_TIMEOUT_S := 5.0
const TURBULENCE_TIMEOUT_BEATS := 8

# --- Stability (GDD §2.4, §3.1) --------------------------------------------
const STABILITY_START := 100.0
## A lost item costs less than a wrong-machine throw: the owner read -8 as an instant
## punishment for not knowing the belts yet.
const STABILITY_FELL_OFF_BELT := -3.0
const STABILITY_WRONG_WASHER := -12.0
const STABILITY_EXPLOSION := -25.0
const STABILITY_CHUTE_DELIVERY := 3.0

# --- Belts (GDD §5.3) -------------------------------------------------------
const BELT_REVERSE_EVERY_MEASURES := 16
const BELT_REVERSE_WARNING_BEATS := 4
const BELT_SPEED := 110.0
const BELT_ACCEL := 900.0
const BELT_SOCK_SPEED_SCALE := 1.6
const PHASE3_WEST_BELT_REVERSED := true

# --- Item physics (GDD §6, §A5, §A7) ---------------------------------------
const THROW_SPEED := 900.0
const THROW_GAS_OFFBEAT_SCALE := 0.5
const HOLD_SPRING := 18.0
const HOLD_MAX_SPEED := 1100.0
const BOOMERANG_ACCEL := 1200.0
const BOOMERANG_DURATION_S := 0.6
const CORE_GRAVITY_RADIUS := 170.0
const CORE_GRAVITY_ACCEL := 220.0
const MAX_ALIVE_ITEMS := 40
const MAX_ITEM_SPEED := 1600.0

# --- Washers, chute and the M4 loop (AGENTS §A5, §A6 #3-#11) -----------------
const WASHER_MOUTH_RADIUS_PX := 60.0
const WASHER_REPAIR_S := 6.0
## UX override of AGENTS §A6 #4: a single loaded item starts washing after this delay, so a
## one-item throw visibly does something. A rhythm strike still starts it instantly.
const WASHER_AUTO_START_S := 1.2
const CHUTE_ACCEPT_RADIUS_PX := 64.0
## First 20 s are onboarding: one item is placed on the floor near Pip so the first
## useful action does not require crossing the room (docs/UX_BIBLE.md §2).
const STARTER_ITEM_AT_S := 1.2
const STARTER_ITEM_ID := &"rocky"
const STARTER_ITEM_COLOR := &"red"
const STARTER_ITEM_PATTERN := &"solid"

# --- Input feel -------------------------------------------------------------
## Presses are buffered this long so an action slightly before it becomes legal still fires.
const INPUT_BUFFER_S := 0.12
## Gamepad aim snaps to an 8-way direction inside this angle (radians) as an assist.
const AIM_SNAP_RAD := 0.21
## A compatible washer mouth inside this angle and range makes the reticle stick to it.
const AIM_STICKY_RAD := 0.32
const AIM_STICKY_RANGE_PX := 420.0

# --- Tutorial (docs/UX_BIBLE.md §7) ----------------------------------------
const TUTORIAL_SEED := 7001
const TUTORIAL_WINDOW_SCALE := 2.0
const TUTORIAL_SOFT_SKIP_S := 12.0
const TUTORIAL_MAX_S := 240.0

# --- UI ---------------------------------------------------------------------
const HUD_SCALE_DEFAULT := 1.0
const HUD_SCALE_OPTIONS: Array[float] = [1.0, 1.25]
const TEXT_SPEED := 0.02

# --- Scoring (GDD §4.3, §A6 #13) -------------------------------------------
const RANK_S_THRESHOLD := 0.85
const RANK_S_ACCURACY := 0.90
const RANK_A_THRESHOLD := 0.65
const RANK_B_THRESHOLD := 0.40

# --- Misc -------------------------------------------------------------------
const ART_SCALE := 4
const ART_CANVAS := Vector2i(320, 180)
const CALIBRATION_DURATION_S := 10.0
const RESTART_MAX_S := 0.5

# --- Open questions as toggles (§A6, §8.2) ---------------------------------
const PHASE_TRANSITION_MODE := TransitionMode.HARD_CUT
const MISS_WASH_PENALTY_S := 0.0
const ENABLE_SUPERNOVA := true
const FINAL_LOAD_COUNTS_DONE_IN_WASHER := false

# --- Scene paths and groups -------------------------------------------------
const SCENE_MAIN := "res://scenes/main/Main.tscn"
const SCENE_MAIN_LEVEL := "res://scenes/main/MainLevel.tscn"
const SCENE_PLAYER := "res://scenes/entities/Player.tscn"
const SCENE_LAUNDRY_ITEM := "res://scenes/entities/LaundryItem.tscn"
const SCENE_WASHER := "res://scenes/entities/CosmicWasher.tscn"

const GROUP_PLAYER := &"player"
const GROUP_ITEMS := &"items"
const GROUP_BELTS := &"belts"
const GROUP_WASHERS := &"washers"
const GROUP_SHREDDERS := &"shredders"
const GROUP_CHUTE := &"chute"

const ITEM_IDS: Array[StringName] = [&"rocky", &"sock", &"moon", &"gas_giant", &"galaxy_core"]
const COLORS: Array[StringName] = [&"red", &"blue", &"yellow"]
const PATTERNS: Array[StringName] = [&"solid", &"ringed", &"spotted"]


## Seconds per beat at a given tempo.
static func beat_seconds(p_bpm: float) -> float:
	if p_bpm <= 0.0:
		return 0.0
	return 60.0 / p_bpm


## Phase index (0-3) for a shift time in seconds.
static func phase_index_at(t: float) -> int:
	var idx := 0
	for i in range(PHASE_START_S.size()):
		if t >= PHASE_START_S[i]:
			idx = i
	return idx


static func phase_start_s(index: int) -> float:
	return PHASE_START_S[clampi(index, 0, PHASE_START_S.size() - 1)]


static func phase_bpm(index: int) -> int:
	return PHASE_BPM[clampi(index, 0, PHASE_BPM.size() - 1)]


static func phase_interval_s(index: int) -> float:
	return PHASE_SPAWN_INTERVAL_S[clampi(index, 0, PHASE_SPAWN_INTERVAL_S.size() - 1)]


## In-game clock as decimal hours in [0, 6].
static func clock_hours(t: float) -> float:
	return clampf(t / SHIFT_DURATION_S, 0.0, 1.0) * GAME_HOURS


## "HH:MM" for the HUD. Floors to whole minutes, so 03:22.5 reads "03:22".
static func clock_string(t: float) -> String:
	var total_minutes := int(floor(clock_hours(t) * 60.0))
	total_minutes = clampi(total_minutes, 0, 6 * 60)
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


## Canonical variant name for item sheets, e.g. "red_solid".
static func variant_name(color: StringName, pattern: StringName) -> StringName:
	return StringName("%s_%s" % [color, pattern])


static func is_known_color(value: StringName) -> bool:
	return COLORS.has(value)


static func is_known_pattern(value: StringName) -> bool:
	return PATTERNS.has(value)
