#!/usr/bin/env python3
"""Measure the tempo, beat phase and downbeat of an audio file.

Usage:
    python3 tools/bpm_analyze.py FILE [FILE ...] [--json] [--start S] [--duration S]
    python3 tools/bpm_analyze.py --selftest

Method (deterministic, no network, no services):

  1. Decode to mono 22.05 kHz PCM with ffmpeg.
  2. Spectral-flux onset envelope (2048-point Hann STFT, hop 256), log-compressed
     so quiet hi-hats survive next to the kick.  A second, low-band (< 250 Hz)
     envelope is kept for downbeat detection.
  3. The envelope is high-passed against a 0.6 s moving average and rectified, so
     slow loudness drift cannot win the autocorrelation.
  4. Coarse tempo: normalised autocorrelation over 60-200 BPM with a harmonic
     comb (1x, 2x, 3x, 4x lag) and a mild log-normal prior around 115 BPM.  This
     is the "onsets -> autocorrelation/comb" stage and the printed `confidence`
     comes from it (winner vs. best tempo at least 6 % away).
  5. Refinement: phase-coherent beat grid.  For each candidate tempo within
     +-3 % of the coarse estimate the onset envelope is sampled at every
     predicted beat over the *whole* track (32 phase offsets), and the best mean
     onset strength wins.  A 0.2 % tempo error smears the grid by half a beat
     over 250 beats, so this pins the tempo to ~0.02 BPM.
  6. Onset-to-grid linear fit: each predicted beat is snapped to the local
     envelope maximum, outliers are rejected, and beat time is regressed on beat
     index.  This is the reported BPM (sub-sample, robust to a missed onset) and
     also yields the beat phase and a residual in ms.
  7. Downbeat: for each of the 4 bar phases, the mean low-band envelope on that
     beat.  The winner is printed with its margin; `--bars` prints per-bar
     energy so a 16-bar window without dropouts can be chosen.

`--selftest` synthesises clicks at 105/118/130/142 BPM (with off-beat hats,
noise and a loudness ramp) and asserts the estimator recovers tempo, phase and
downbeat.  It exits non-zero if any case fails.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

MIN_BPM = 60.0
MAX_BPM = 200.0
ANALYSIS_SR = 22050
HOP = 256
WIN = 2048
PRIOR_CENTER_BPM = 115.0
PRIOR_SIGMA_LN = 0.32          # ~+-38 %, deliberately weak
COARSE_RIVAL_MIN_REL = 0.06    # "a different tempo" = 6 % away
FINE_SPAN = 0.03               # +-3 % around the coarse estimate
FINE_STEP = 0.02               # BPM
GRID_PHASES = 32


# --------------------------------------------------------------------------- io

def require_ffmpeg() -> None:
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            sys.exit(f"error: {tool} not found on PATH")


def decode_mono(path: str, start: float | None, duration: float | None) -> tuple[np.ndarray, int]:
    """Decode `path` to a float32 mono array at ANALYSIS_SR via ffmpeg."""
    require_ffmpeg()
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "analysis.wav")
        cmd = ["ffmpeg", "-nostdin", "-v", "error", "-y"]
        if start is not None:
            cmd += ["-ss", f"{start:.3f}"]
        if duration is not None:
            cmd += ["-t", f"{duration:.3f}"]
        cmd += ["-i", path, "-vn", "-ac", "1", "-ar", str(ANALYSIS_SR),
                "-c:a", "pcm_s16le", wav_path]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            sys.exit(f"error: ffmpeg failed for {path}: {proc.stderr.strip()}")
        with wave.open(wav_path, "rb") as wf:
            if wf.getframerate() != ANALYSIS_SR:
                sys.exit(f"error: unexpected sample rate {wf.getframerate()}")
            raw = wf.readframes(wf.getnframes())
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if samples.size < ANALYSIS_SR:
        sys.exit(f"error: {path} is too short to analyse (< 1 s)")
    return samples, ANALYSIS_SR


# ------------------------------------------------------------------- analysis

def _spectra(samples: np.ndarray) -> tuple[np.ndarray, int]:
    if samples.size < WIN:
        samples = np.pad(samples, (0, WIN - samples.size))
    n_frames = 1 + (samples.size - WIN) // HOP
    frames = np.lib.stride_tricks.as_strided(
        samples,
        shape=(n_frames, WIN),
        strides=(samples.strides[0] * HOP, samples.strides[0]),
        writeable=False,
    )
    window = np.hanning(WIN).astype(np.float32)
    return np.abs(np.fft.rfft(frames * window, axis=1)).astype(np.float32), n_frames


def onset_envelopes(samples: np.ndarray, sr: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, float]:
    """Return (full-band flux, low-band energy, low-band flux, frames per second).

    The low-band *energy* is kept un-log-compressed on purpose: log compression
    flattens the downbeat accent (a kick 40 % louder barely changes the flux), so
    accent detection needs the linear amplitude.

    Frame i covers samples [i*HOP, i*HOP+WIN), so its centre is at
    i*HOP + WIN/2.  The envelopes are delayed by WIN/2 frames so that index j
    corresponds to time j/fps; without this 46 ms correction every measured
    phase and downbeat is systematically early.
    """
    lin, n_frames = _spectra(samples)
    bin_hz = sr / WIN
    low_bins = max(2, int(250.0 / bin_hz))
    low_energy = lin[:, :low_bins].sum(axis=1).astype(np.float64)
    mag = np.log1p(lin * 8.0)
    diff = np.diff(mag, axis=0)
    np.maximum(diff, 0.0, out=diff)
    flux = np.zeros(n_frames, dtype=np.float32)
    flux[1:] = diff.sum(axis=1)

    low = np.zeros(n_frames, dtype=np.float32)
    low[1:] = diff[:, :low_bins].sum(axis=1)

    kernel = np.array([0.25, 0.5, 1.0, 0.5, 0.25], dtype=np.float32)
    kernel /= kernel.sum()
    flux = np.convolve(flux, kernel, mode="same")
    low = np.convolve(low, kernel, mode="same")

    delay = int(round(0.5 * WIN / HOP))
    pad = np.zeros(delay, dtype=np.float32)
    flux = np.concatenate([pad, flux[:-delay]])
    low = np.concatenate([pad, low[:-delay]])

    # Normalise the low-band energy against its own slow trend so a loudness
    # ramp cannot masquerade as an accent.
    w = max(3, int(round(1.5 * sr / HOP)) | 1)
    padn = w // 2
    csum = np.cumsum(np.insert(np.pad(low_energy, (padn, padn), mode="edge"), 0, 0.0))
    trend = (csum[w:] - csum[:-w]) / w
    low_energy = low_energy / np.maximum(trend, 1e-9)
    low_energy = np.concatenate([np.zeros(delay), low_energy[:-delay]])
    return (flux.astype(np.float64), low_energy.astype(np.float64),
            low.astype(np.float64), sr / HOP)


def highpass(env: np.ndarray, fps: float, window_s: float = 0.6) -> np.ndarray:
    """Subtract a moving average and half-wave rectify (kills loudness drift)."""
    w = max(3, int(round(window_s * fps)) | 1)
    pad = w // 2
    padded = np.pad(env, (pad, pad), mode="edge")
    csum = np.cumsum(np.insert(padded, 0, 0.0))
    mean = (csum[w:] - csum[:-w]) / w
    out = env - mean
    return np.maximum(out, 0.0)


def normalised_acf(env: np.ndarray) -> np.ndarray:
    n = env.size
    nfft = 1 << int(math.ceil(math.log2(2 * n)))
    spec = np.fft.rfft(env, nfft)
    full = np.fft.irfft(spec * np.conj(spec), nfft)[:n]
    denom = np.maximum(n - np.arange(n), 1).astype(np.float64)
    full = full / denom
    return full / (full[0] if full[0] else 1.0)


def comb_score(acf: np.ndarray, lag: float) -> float:
    """Harmonic comb on the ACF: the lag plus its 2x/3x/4x multiples."""
    score = 0.0
    weight = 1.0
    n = acf.size
    for k in (1, 2, 3, 4):
        pos = lag * k
        if pos >= n - 2:
            break
        i = int(math.floor(pos))
        frac = pos - i
        score += weight * (acf[i] * (1.0 - frac) + acf[i + 1] * frac)
        weight *= 0.5
    return score


def coarse_tempo(env: np.ndarray, fps: float) -> dict:
    acf = normalised_acf(env)
    min_lag = int(math.floor(fps * 60.0 / MAX_BPM))
    max_lag = min(int(math.ceil(fps * 60.0 / MIN_BPM)), env.size // 3)
    if min_lag < 2 or max_lag <= min_lag:
        return {"bpm": 0.0, "confidence": 0.0, "candidates": []}
    lags = np.arange(min_lag, max_lag + 1)
    raw = np.array([comb_score(acf, float(lag)) for lag in lags])
    tempos = 60.0 * fps / lags
    prior = np.exp(-0.5 * (np.log(tempos / PRIOR_CENTER_BPM) / PRIOR_SIGMA_LN) ** 2)
    scores = raw * prior

    order = np.argsort(scores)[::-1]
    best_i = int(order[0])
    best_lag = float(lags[best_i])
    if 0 < best_i < lags.size - 1:  # parabolic refinement in lag space
        y0, y1, y2 = scores[best_i - 1], scores[best_i], scores[best_i + 1]
        den = y0 - 2.0 * y1 + y2
        if abs(den) > 1e-12:
            best_lag += 0.5 * (y0 - y2) / den
    best_tempo = 60.0 * fps / best_lag

    candidates: list[dict] = []
    for idx in order:
        t = float(tempos[idx])
        if any(abs(t - c["bpm"]) < 1.5 for c in candidates):
            continue
        candidates.append({"bpm": round(t, 2), "score": round(float(scores[idx]), 4)})
        if len(candidates) >= 4:
            break

    rival = 0.0
    for cand in candidates[1:]:
        if abs(cand["bpm"] - best_tempo) / best_tempo >= COARSE_RIVAL_MIN_REL:
            rival = max(rival, cand["score"])
            break
    confidence = 0.0 if scores[best_i] <= 0 else \
        (float(scores[best_i]) - rival) / abs(float(scores[best_i]))
    return {
        "bpm": round(float(best_tempo), 2),
        "confidence": round(float(confidence), 3),
        "candidates": candidates,
        "raw_peak": round(float(raw[best_i]), 4),
    }


def grid_mean(env: np.ndarray, fps: float, bpm: float) -> tuple[float, float]:
    """Best mean onset strength over 32 beat-grid phases. Returns (score, phase_s)."""
    period = 60.0 / bpm * fps
    n = env.size
    n_beats = int((n - 1) / period)
    if n_beats < 8:
        return -1.0, 0.0
    base = np.arange(n_beats, dtype=np.float64) * period
    best = (-1.0, 0.0)
    for k in range(GRID_PHASES):
        phase = k * period / GRID_PHASES
        idx = base + phase
        vals = np.interp(idx, np.arange(n), env)
        s = float(vals.mean())
        if s > best[0]:
            best = (s, phase / fps)
    return best


def refine(env: np.ndarray, fps: float, bpm0: float) -> dict:
    """Phase-coherent grid search around bpm0, then onset-to-grid linear fit."""
    lo, hi = bpm0 * (1.0 - FINE_SPAN), bpm0 * (1.0 + FINE_SPAN)
    step = FINE_STEP
    best = (-1.0, bpm0, 0.0)
    b = lo
    while b <= hi + 1e-9:
        s, ph = grid_mean(env, fps, b)
        if s > best[0]:
            best = (s, b, ph)
        b += step
    grid_score, grid_bpm, grid_phase = best

    fit = fit_beats(env, fps, grid_bpm, grid_phase)
    bpm = fit["bpm"] if fit["ok"] else grid_bpm
    return {
        "bpm": round(bpm, 3),
        "grid_bpm": round(grid_bpm, 3),
        "grid_score": round(grid_score, 5),
        "phase_s": fit.get("phase_s", grid_phase),
        "fit": fit,
        "coherence": coherence(env, fps, bpm),
    }


def coherence(env: np.ndarray, fps: float, bpm: float) -> float:
    """Peak-vs-neighbours contrast of the coherent grid score at this tempo."""
    scores = []
    for rel in (-0.004, -0.002, 0.0, 0.002, 0.004):
        s, _ = grid_mean(env, fps, bpm * (1.0 + rel))
        scores.append(s)
    mid = scores[2]
    side = max(scores[0], scores[1], scores[3], scores[4])
    if mid <= 0:
        return 0.0
    return float((mid - side) / mid)


def fit_beats(env: np.ndarray, fps: float, bpm: float, phase_s: float,
              half_beats: float = 0.25) -> dict:
    """Snap predicted beats to local onset maxima and regress time on beat index."""
    period = 60.0 / bpm
    period_f = period * fps
    n = env.size
    n_beats = int((n - 1) / period_f)
    if n_beats < 16:
        return {"ok": False, "n_beats": n_beats}
    phase_f = phase_s * fps
    half = half_beats * period_f
    idx, times, strengths = [], [], []
    for k in range(n_beats):
        centre = phase_f + k * period_f
        lo = int(max(0, math.floor(centre - half)))
        hi = int(min(n - 1, math.ceil(centre + half)))
        if hi <= lo:
            continue
        seg = env[lo:hi]
        j = int(np.argmax(seg))
        strength = float(seg[j])
        pos = float(lo + j)
        if 0 < j < seg.size - 1:  # parabolic sub-frame peak
            y0, y1, y2 = seg[j - 1], seg[j], seg[j + 1]
            den = y0 - 2.0 * y1 + y2
            if abs(den) > 1e-12:
                pos += 0.5 * (y0 - y2) / den
        idx.append(k)
        times.append(pos / fps)
        strengths.append(strength)
    if len(idx) < 16:
        return {"ok": False, "n_beats": len(idx)}
    idx_a = np.asarray(idx, dtype=np.float64)
    t_a = np.asarray(times, dtype=np.float64)
    s_a = np.asarray(strengths, dtype=np.float64)
    good = s_a >= np.percentile(s_a, 25)  # drop silent / missing onsets
    for _ in range(3):
        if good.sum() < 8:
            break
        slope, intercept = np.polyfit(idx_a[good], t_a[good], 1)
        residual = t_a - (intercept + slope * idx_a)
        mad = np.median(np.abs(residual[good])) or 1e-3
        good = np.abs(residual) < max(3.0 * mad, 0.02)
    if good.sum() < 8:
        return {"ok": False, "n_beats": int(good.sum())}
    slope, intercept = np.polyfit(idx_a[good], t_a[good], 1)
    residual = (t_a - (intercept + slope * idx_a))[good] * 1000.0
    if slope <= 0:
        return {"ok": False, "n_beats": int(good.sum())}
    return {
        "ok": True,
        "bpm": 60.0 / slope,
        "phase_s": float(intercept),
        "n_beats": int(good.sum()),
        "residual_ms_median": round(float(np.median(np.abs(residual))), 2),
        "residual_ms_p95": round(float(np.percentile(np.abs(residual), 95)), 2),
    }


def downbeat(low_env: np.ndarray, fps: float, bpm: float, phase_s: float) -> dict:
    """Pick the bar phase whose beats carry the most low-frequency (kick) energy.

    Anchoring on the first strong low-band hit instead of on the fitted beat 0
    removes the +-1 beat ambiguity that a wrapped phase would introduce.
    """
    period = 60.0 / bpm * fps
    n = low_env.size
    n_beats = int((n - 1) / period)
    phase_f = phase_s * fps
    search = low_env[:max(1, int(min(4.0 * fps, low_env.size * 0.4)))]
    if not np.any(search):
        return {"bar_phase": 0, "bar_phase_scores": [0.0] * 4, "margin": 0.0,
                "anchor_s": 0.0, "downbeat_s": phase_s}
    k0 = int(round((float(np.argmax(search)) - phase_f) / period))
    collected: list[list[float]] = [[], [], [], []]
    for m in range(4):
        k = k0 + m
        while 0 <= k < n_beats:
            centre = phase_f + k * period
            lo = int(max(0, math.floor(centre - 0.2 * period)))
            hi = int(min(n, math.ceil(centre + 0.2 * period)))
            if hi > lo:
                collected[m].append(float(low_env[lo:hi].max()))
            k += 4
    means = np.array([np.median(c) if c else 0.0 for c in collected])
    total = float(means.sum())
    order = np.argsort(means)[::-1]
    best = int(order[0])
    margin = float((means[best] - means[order[1]]) / total) if total > 0 else 0.0
    downbeat_f = phase_f + (k0 + best) * period
    bar_s = 240.0 / bpm
    # Signed distance to the nearest downbeat on the grid: consumers should use
    # this (or downbeat_s) rather than bar_phase, which is anchored to the
    # arbitrary fitted beat 0.
    offset = ((downbeat_f / fps) + 0.5 * bar_s) % bar_s - 0.5 * bar_s
    return {
        "bar_phase": best,
        "bar_phase_scores": [round(float(m), 4) for m in means],
        "margin": round(margin, 4),
        "anchor_s": round(float(np.argmax(search)) / fps, 4),
        "downbeat_offset_s": round(offset, 4),
        "downbeat_s": round(offset % bar_s, 4),
    }


def attack_time(samples: np.ndarray, sr: int, t_guess: float, radius_s: float = 0.05) -> float:
    """Sample-domain onset search: steepest 1 ms energy rise within +-radius of t_guess.

    The spectral-flux envelope peaks ~1-2 STFT frames after the physical attack, so
    trimming on the raw estimate would start the loop 15-20 ms late.  This refines
    the cut point to the actual attack (about +-1 ms).
    """
    r = int(radius_s * sr)
    c = int(round(t_guess * sr))
    lo = max(0, c - r)
    hi = min(samples.size, c + r)
    if hi - lo < 8:
        return t_guess
    seg = samples[lo:hi].astype(np.float64)
    hop = max(1, int(0.001 * sr))
    n = seg.size // hop
    if n < 4:
        return t_guess
    energy = np.sqrt(np.mean(seg[: n * hop].reshape(n, hop) ** 2, axis=1))
    rise = np.diff(energy, prepend=energy[0])
    j = int(np.argmax(rise))
    return (lo + j * hop) / sr


def energy_onsets(samples: np.ndarray, sr: int, win_s: float = 0.010,
                  hop_s: float = 0.002) -> tuple[np.ndarray, float]:
    """Sample-domain onset strength: positive change of short-time RMS.

    Independent of the STFT flux (and therefore of its window smear), this is the
    right envelope for asking *where in the file* the attacks actually are.
    """
    mono = samples if samples.ndim == 1 else samples.mean(axis=1)
    win = max(4, int(win_s * sr))
    hop = max(1, int(hop_s * sr))
    if mono.size < win + hop:
        return np.zeros(1, dtype=np.float64), sr / hop
    n = 1 + (mono.size - win) // hop
    squares = np.concatenate([[0.0], np.cumsum(mono.astype(np.float64) ** 2)])
    idx = np.arange(n) * hop
    energy = np.sqrt(np.maximum(squares[idx + win] - squares[idx], 0.0) / win)
    log_e = np.log(energy + 1e-9)
    strength = np.maximum(np.diff(log_e, prepend=log_e[0]), 0.0)
    # Light 3-tap smoothing keeps a single attack from splitting in two.
    strength = np.convolve(strength, np.array([0.25, 0.5, 0.25]), mode="same")
    return strength, sr / hop


def start_attack(samples: np.ndarray, sr: int) -> dict:
    """Describe the attack at the very beginning of a file.

    A loop trimmed on a downbeat must open with a transient: energy in the first
    ~60 ms has to rise well above the level of the first couple of milliseconds
    (the 5 ms fade-in intentionally mutes that first sliver).
    """
    mono = samples if samples.ndim == 1 else samples.mean(axis=1)
    hop = max(1, int(0.001 * sr))
    head = mono[: int(0.12 * sr)]
    n = head.size // hop
    if n < 8:
        return {"attack_ms": -1.0, "rise_db": 0.0, "peak_ms": -1.0}
    blocks = head[: n * hop].reshape(n, hop)
    rms = np.sqrt(np.mean(blocks.astype(np.float64) ** 2, axis=1))
    base = float(np.mean(rms[:2])) if n >= 2 else 1e-9
    window = rms[: min(n, 60)]
    peak = float(np.max(window))
    return {
        "attack_ms": round(float(np.argmax(np.diff(rms[:60], prepend=rms[0]))) * hop / sr * 1000.0, 2),
        "peak_ms": round(float(np.argmax(window)) * hop / sr * 1000.0, 2),
        "rise_db": round(20.0 * math.log10(max(1e-9, peak / max(1e-9, base))), 2),
    }


def verify_grid(samples: np.ndarray, sr: int, bpm: float) -> dict:
    """Check that onsets land on a beat grid at a *known* tempo.

    Blind tempo estimation is ambiguous on short loops (a groove repeats at
    several metrical levels), so shipped stems are verified against their target
    BPM instead: pick the best phase, snap every predicted beat to the local
    envelope maximum and report how tightly they fit the straight line.
    """
    env_full, _low_env, _low_flux, fps = onset_envelopes(samples, sr)
    env = highpass(env_full, fps)
    period = 60.0 / bpm
    expected = max(1, int((env.size - 1) / (period * fps)))

    # Scan the whole period at fine resolution: the correct grid is the one whose
    # snapped onsets fit a straight line, and a +-0.15 beat snap window cannot
    # reach the neighbouring beat (so off-beats cannot win).
    best = None
    for k in range(64):
        phase = (k / 64.0) * period
        fit = fit_beats(env, fps, bpm, phase, half_beats=0.15)
        if not fit.get("ok") or fit["n_beats"] < 0.5 * expected:
            continue
        key = (fit["residual_ms_p95"], -fit["n_beats"])
        if best is None or key < best[0]:
            best = (key, fit, phase)
    if best is None:
        grid_score, _ = grid_mean(env, fps, bpm)
        return {"bpm": bpm, "ok": False, "n_beats": 0,
                "grid_score": round(grid_score, 5)}
    _, fit, phase = best
    attack = start_attack(samples, sr)
    return {
        "bpm": bpm, "ok": True, "n_beats": fit["n_beats"],
        "phase_s": round(fit["phase_s"], 4),   # beat-index ambiguous, info only
        "residual_ms_median": fit["residual_ms_median"],
        "residual_ms_p95": fit["residual_ms_p95"],
        "attack_ms": attack["attack_ms"],
        "attack_peak_ms": attack["peak_ms"],
        "attack_rise_db": attack["rise_db"],
    }


def snap_bpm(bpm: float, tol: float = 0.06) -> tuple[float, bool]:
    nearest = round(bpm)
    if abs(bpm - nearest) <= tol:
        return float(nearest), True
    return bpm, False


def bar_energies(samples: np.ndarray, sr: int, bpm: float, downbeat_s: float) -> list[dict]:
    """Per-bar RMS and onset strength, to choose a clean 16-bar window."""
    bar_s = 4.0 * 60.0 / bpm
    out = []
    n = samples.size
    i = 0
    t = downbeat_s
    while t + bar_s <= n / sr + 1e-9:
        a = int(round(t * sr))
        b = int(round((t + bar_s) * sr))
        seg = samples[a:b]
        rms = float(np.sqrt(np.mean(seg.astype(np.float64) ** 2)) + 1e-12)
        out.append({"bar": i, "start_s": round(t, 3), "rms_db": round(20 * math.log10(rms), 1)})
        i += 1
        t += bar_s
    return out


def estimate(samples: np.ndarray, sr: int) -> dict:
    env_full, env_low, _low_flux, fps = onset_envelopes(samples, sr)
    env = highpass(env_full, fps)
    if not np.any(env):
        return {"bpm": 0.0, "confidence": 0.0, "candidates": []}
    coarse = coarse_tempo(env, fps)
    if coarse["bpm"] <= 0:
        return coarse
    fine = refine(env, fps, coarse["bpm"])
    bpm = fine["bpm"]
    snapped, did_snap = snap_bpm(bpm)
    phase_raw = fine["phase_s"]          # may be negative: beat 0 can precede t=0
    phase = phase_raw % (60.0 / snapped)
    info = {
        "bpm": round(snapped, 2),
        "bpm_raw": round(bpm, 3),
        "snapped": did_snap,
        "confidence": coarse["confidence"],
        "coherence": round(fine["coherence"], 3),
        "beat_phase_s": round(phase, 4),
        "beat_seconds": round(60.0 / snapped, 4),
        "bar_seconds": round(240.0 / snapped, 4),
        "coarse_bpm": coarse["bpm"],
        "candidates": coarse["candidates"],
        "fit": fine["fit"],
        "frame_rate": round(fps, 3),
        "envelope_frames": int(env.size),
    }
    if fine["fit"].get("ok"):
        db = downbeat(env_low, fps, snapped, phase_raw)
        offset = db["downbeat_offset_s"]
        bar = 240.0 / snapped
        first = offset if offset >= 0.0 else offset + bar
        db["first_downbeat_s"] = round(first, 4)
        db["first_downbeat_transient_s"] = round(attack_time(samples, sr, first), 4)
        info["downbeat"] = db
    return info


# ------------------------------------------------------------------ self test

def _clicks(bpm: float, seconds: float, sr: int) -> np.ndarray:
    """Synthetic funk-ish test signal: accented kick on 1, snare on 2/4, hats on 8ths."""
    rng = np.random.default_rng(7)
    n = int(seconds * sr)
    out = np.zeros(n, dtype=np.float64)

    kl = int(0.30 * sr)
    kt = np.arange(kl) / sr
    kf = 110.0 * np.exp(-kt / 0.02) + 48.0
    kick = np.sin(2 * np.pi * np.cumsum(kf) / sr) * np.exp(-kt / 0.075)
    kick *= np.minimum(1.0, kt / 0.001)

    sl = int(0.18 * sr)
    st = np.arange(sl) / sr
    snare = (rng.standard_normal(sl) * 0.7 + np.sin(2 * np.pi * 190 * st) * 0.5)
    snare *= np.exp(-st / 0.045)

    hat = rng.standard_normal(int(0.035 * sr)) * np.exp(-np.arange(int(0.035 * sr)) / (0.005 * sr))

    beat = int(round(60.0 / bpm * sr))
    for k in range(int(seconds * bpm / 60.0)):
        pos = k * beat
        amp = 1.0 if k % 4 == 0 else 0.6
        if pos + kick.size < n:
            out[pos:pos + kick.size] += 0.9 * amp * kick
        if k % 4 in (1, 3) and pos + snare.size < n:
            out[pos:pos + snare.size] += 0.35 * snare
        for off in (0, beat // 2):
            h = pos + off
            if h + hat.size < n:
                out[h:h + hat.size] += 0.06 * hat
    out *= np.linspace(0.4, 1.0, n)          # loudness drift the HP filter must ignore
    out += 0.002 * rng.standard_normal(n)
    return (out / max(1e-9, np.max(np.abs(out))) * 0.7).astype(np.float32)


def selftest() -> int:
    sr = ANALYSIS_SR
    failures = 0
    for bpm in (105.0, 118.0, 130.0, 142.0):
        samples = _clicks(bpm, 40.0, sr)
        info = estimate(samples, sr)
        err = abs(info["bpm"] - bpm)
        got_phase = info.get("beat_phase_s", -1.0)
        db_off = info.get("downbeat", {}).get("downbeat_offset_s", 9.0)
        ok = err <= 0.12 and 0.0 <= got_phase < 60.0 / bpm and abs(db_off) <= 0.03
        failures += 0 if ok else 1
        print(f"selftest {bpm:6.1f} BPM -> {info['bpm']:7.2f} (err {err:.3f}) "
              f"phase {got_phase:.4f}s downbeat_off {db_off:+.3f}s confidence "
              f"{info['confidence']:.2f} coherence {info['coherence']:.2f} "
              f"{'PASS' if ok else 'FAIL'}")
    print(f"selftest: {'PASS' if failures == 0 else 'FAIL'} ({failures} failures)")
    return 0 if failures == 0 else 1


# ------------------------------------------------------------------------- cli

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Measure tempo, beat phase and downbeat.")
    parser.add_argument("files", nargs="*", help="audio file(s) to analyse")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--start", type=float, default=None, help="start offset (s)")
    parser.add_argument("--duration", type=float, default=None, help="analyse only N seconds")
    parser.add_argument("--bars", action="store_true", help="print per-bar RMS")
    parser.add_argument("--selftest", action="store_true", help="run the synthetic click test")
    parser.add_argument("--known-bpm", type=float, default=None,
                        help="verify a known tempo instead of estimating it")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()
    if not args.files:
        parser.error("no input files (or use --selftest)")

    results = []
    for path in args.files:
        if not os.path.isfile(path):
            sys.exit(f"error: no such file: {path}")
        samples, sr = decode_mono(path, args.start, args.duration)
        if args.known_bpm is not None:
            info = verify_grid(samples, sr, args.known_bpm)
            info["file"] = path
            info["analysed_s"] = round(samples.size / sr, 3)
            results.append(info)
            if not args.json:
                if info["ok"]:
                    print(f"{os.path.basename(path)}: {info['bpm']:.2f} BPM grid, "
                          f"{info['n_beats']} beats, residual "
                          f"{info['residual_ms_median']} ms median / "
                          f"{info['residual_ms_p95']} ms p95, "
                          f"attack peak {info['attack_peak_ms']:.0f} ms (+{info['attack_rise_db']:.1f} dB)")
                else:
                    print(f"{os.path.basename(path)}: no stable grid at "
                          f"{info['bpm']:.2f} BPM ({info['n_beats']} beats)")
            continue
        info = estimate(samples, sr)
        info["file"] = path
        info["analysed_s"] = round(samples.size / sr, 3)
        info["peak_dbfs"] = round(float(20 * math.log10(max(1e-9, np.max(np.abs(samples))))), 2)
        if args.bars and info.get("downbeat"):
            info["bars"] = bar_energies(samples, sr, info["bpm"], info["downbeat"]["downbeat_s"])
        results.append(info)
        if not args.json:
            print(os.path.basename(path))
            print(f"  tempo      : {info['bpm']:.2f} BPM"
                  f"{' (snapped from %s)' % info['bpm_raw'] if info.get('snapped') else ''}")
            print(f"  confidence : {info['confidence']:.3f}  (coherence {info['coherence']:.2f})")
            print(f"  beat       : {info['beat_seconds']:.4f} s   bar {info['bar_seconds']:.4f} s")
            print(f"  beat phase : {info['beat_phase_s']:.4f} s")
            if info.get("downbeat"):
                d = info["downbeat"]
                print(f"  downbeat   : first at {d['first_downbeat_s']:.3f} s "
                      f"(attack {d['first_downbeat_transient_s']:.4f} s), offset "
                      f"{d['downbeat_offset_s']:+.4f} s, bar scores {d['bar_phase_scores']}")
            fit = info.get("fit", {})
            if fit.get("ok"):
                print(f"  fit        : {fit['n_beats']} beats, residual "
                      f"{fit['residual_ms_median']} ms median / {fit['residual_ms_p95']} ms p95")
            others = ", ".join(f"{c['bpm']:.1f}" for c in info["candidates"][1:])
            print(f"  runners-up : {others or 'none'}")
            if args.bars and "bars" in info:
                print("  bars       : " + " ".join(f"{b['rms_db']:.0f}" for b in info["bars"]))
    if args.json:
        print(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
