class_name CalibrationMath
extends RefCounted
## Pure tap-calibration math for the 10 s audio wizard (GDD §5.1, docs/CALIBRATION.md).
##
## The player taps along with the click track; every tap is reduced to a signed offset
## from the nearest beat, folded into `[-T/2, +T/2)`. A positive offset means the tap
## landed *after* the beat, which is what an output-latency under-report also looks like.
## `BeatConductor.get_song_time()` subtracts the resulting offset, so a positive median
## pulls the musical clock back and the player's late taps then read as on-beat.
##
## No scene, audio or autoload access: every function is static and unit-testable.

## Hard clamp for the persisted user offset (Settings also clamps to ±0.5 s).
const MAX_OFFSET_MS := 500.0
## Below this many taps the result is shown but cannot be applied.
const MIN_SAMPLES := 3
## Robust outlier cut-off: median ± K · 1.4826 · MAD (1.4826 makes MAD a σ estimate).
const MAD_OUTLIER_SCALE := 3.0
## Floor for the MAD tolerance so a near-constant tap set still rejects gross blunders.
const MIN_MAD_MS := 1.0
## Scale factor that turns a median absolute deviation into a Gaussian σ estimate.
const MAD_TO_SIGMA := 1.4826


## Folds `seconds` into [-period/2, +period/2). `+period/2` maps to `-period/2`.
static func wrap_signed(seconds: float, period: float) -> float:
	if period <= 0.0:
		return 0.0
	var half := period * 0.5
	return fposmod(seconds + half, period) - half


## Signed distance from `tap_time` to the nearest beat, in seconds.
## Positive = tap after the beat; the range is [-T/2, +T/2).
static func beat_error(tap_time: float, beat_seconds: float) -> float:
	return wrap_signed(tap_time, beat_seconds)


## One wizard sample: the tap's signed offset from the nearest beat, in milliseconds.
static func sample_offset_ms(tap_time: float, beat_seconds: float) -> float:
	return s_to_ms(beat_error(tap_time, beat_seconds))


## Reduces absolute tap times to per-tap offsets in milliseconds.
static func samples_from_taps(taps: Array[float], beat_seconds: float) -> Array[float]:
	var samples: Array[float] = []
	for tap in taps:
		samples.append(sample_offset_ms(tap, beat_seconds))
	return samples


## Median of the samples. Returns 0.0 for an empty set (even count averages the middle).
static func median(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array[float] = []
	sorted.assign(samples)
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


## Median absolute deviation around `median(samples)`.
static func mad(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var centre := median(samples)
	var deviations: Array[float] = []
	for value in samples:
		deviations.append(absf(value - centre))
	return median(deviations)


## Drops samples further than `MAD_OUTLIER_SCALE` robust σ from the median.
## Keeps everything when there is nothing to compare against (fewer than 3 samples).
static func reject_outliers(samples: Array[float]) -> Array[float]:
	var kept: Array[float] = []
	if samples.size() < 3:
		kept.assign(samples)
		return kept
	var centre := median(samples)
	var limit := maxf(MAD_OUTLIER_SCALE * MAD_TO_SIGMA * mad(samples), MIN_MAD_MS)
	for value in samples:
		if absf(value - centre) <= limit:
			kept.append(value)
	if kept.is_empty():
		kept.assign(samples)
	return kept


## Final wizard result: outlier-rejected median, clamped to ±MAX_OFFSET_MS.
static func resolve_offset_ms(samples: Array[float]) -> float:
	return clamp_offset_ms(median(reject_outliers(samples)))


## Clamped offset in milliseconds, for the value that is persisted in Settings.
static func clamp_offset_ms(ms: float) -> float:
	return clampf(ms, -MAX_OFFSET_MS, MAX_OFFSET_MS)


## True when there are enough taps for a trustworthy median.
static func has_enough_samples(samples: Array[float]) -> bool:
	return samples.size() >= MIN_SAMPLES


static func ms_to_s(ms: float) -> float:
	return ms / 1000.0


static func s_to_ms(seconds: float) -> float:
	return seconds * 1000.0
