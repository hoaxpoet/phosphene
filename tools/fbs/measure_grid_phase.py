#!/usr/bin/env python3
"""FBS Stage 0 — Measure the cached BeatGrid's accuracy against real audio onsets.

Two load-bearing questions the FFO Beat-Sync proposal rests on:

  Q1. Is the pre-analysed (cached) BeatGrid actually accurate on local files?
      -> compare the grid's predicted beat positions to where the real kicks
         land in `raw_tap.wav` (PCM ground truth). Decompose into TEMPO
         (does the grid's BPM match the music's beat rate?) and PHASE (is the
         grid's "one" where the music's "one" is, or off by a constant?).
  Q2. Is the first strong hit cleanly detectable as the anchor?
      -> find the first strong onset after track start; is it isolated and at
         a sane time?

Plus a supporting measurement the proposal leans on heavily:

  WANDER. How far does the LIVE drift tracker (`drift_ms`) move over the
          opening? (motivates "hold the pulse steady; don't chase the live
          phase"). Read straight from features.csv — no audio needed.

Ground truth is the PCM in `raw_tap.wav` (IEEE float32 stereo, the first 30 s
of the session's first track). The cached grid's per-frame output is in
`features.csv` (`grid_bpm`, `beatPhase01`, `drift_ms`, `lock_state`).

Pure Python stdlib. Diagnostic artifact for the FBS (Ferrofluid Beat Sync) work.

Usage:
    python3 measure_grid_phase.py <session_dir> [--track-index N] [--label NAME]
"""
import argparse
import csv
import math
import os
import re
import struct
import wave

# ---------------------------------------------------------------------------
# WAV reader (IEEE float32 or PCM16/24/32), returns mono float list + samplerate
# ---------------------------------------------------------------------------

def read_wav_mono(path):
    """Read a WAV (float32 or int PCM) and return (mono_samples, sample_rate)."""
    with open(path, "rb") as f:
        riff = f.read(12)
        assert riff[0:4] == b"RIFF" and riff[8:12] == b"WAVE", "not a WAVE file"
        fmt = None
        data = None
        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            cid, sz = struct.unpack("<4sI", hdr)
            if cid == b"fmt ":
                fmt = f.read(sz)
            elif cid == b"data":
                data = f.read(sz)
                break
            else:
                f.seek(sz, 1)
        af, ch, sr, _br, _ba, bps = struct.unpack("<HHIIHH", fmt[:16])

    if af == 3 and bps == 32:                       # IEEE float32
        n = len(data) // 4
        vals = struct.unpack("<%df" % n, data[: n * 4])
    elif af == 1 and bps == 16:                     # PCM16
        n = len(data) // 2
        vals = [v / 32768.0 for v in struct.unpack("<%dh" % n, data[: n * 2])]
    else:
        raise ValueError(f"unsupported WAV: audioFormat={af} bits={bps}")

    if ch == 1:
        mono = list(vals)
    else:
        mono = [0.5 * (vals[i] + vals[i + 1]) for i in range(0, len(vals) - 1, ch)]
    return mono, sr


# ---------------------------------------------------------------------------
# Spectral-flux onset envelope (full-band) — the standard onset-detection
# function a beat tracker sees: STFT magnitude, half-wave-rectified positive
# bin-to-bin difference summed across bins. Picks up drums, guitar attacks,
# piano, etc. — not just kicks. Needs an FFT.
# ---------------------------------------------------------------------------
import cmath

HOP = 512    # ~11.6 ms at 44.1 kHz
WIN = 1024   # ~23 ms window


def _fft(x):
    """In-place iterative radix-2 Cooley-Tukey FFT (len(x) must be a power of 2)."""
    n = len(x)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            x[i], x[j] = x[j], x[i]
    length = 2
    while length <= n:
        wlen = cmath.exp(-2j * math.pi / length)
        half = length >> 1
        for i in range(0, n, length):
            w = 1 + 0j
            for k in range(half):
                u = x[i + k]
                v = x[i + k + half] * w
                x[i + k] = u + v
                x[i + k + half] = u - v
                w *= wlen
        length <<= 1
    return x


# precomputed Hann window
_HANN = [0.5 - 0.5 * math.cos(2.0 * math.pi * n / (WIN - 1)) for n in range(WIN)]


def onset_envelope(mono, sr):
    """Return (env, fps): full-band spectral-flux onset function, per HOP."""
    nframes = max(0, (len(mono) - WIN) // HOP + 1)
    nbins = WIN // 2
    env = [0.0] * nframes
    prev = [0.0] * nbins
    for k in range(nframes):
        base = k * HOP
        buf = [complex(mono[base + n] * _HANN[n], 0.0) for n in range(WIN)]
        _fft(buf)
        flux = 0.0
        cur = [0.0] * nbins
        for b in range(nbins):
            # log-compress: a kick's big RELATIVE low-band jump isn't swamped by
            # the absolute high-band energy of distorted/loud material. (Raw
            # linear flux let distortion fizz dominate -> R collapsed on rock.)
            m = math.log1p(50.0 * abs(buf[b]))
            cur[b] = m
            d = m - prev[b]
            if d > 0.0:
                flux += d
        prev = cur
        env[k] = flux
    fps = sr / HOP
    # High-pass (local-mean subtraction, ~0.12 s) + half-wave rectify. Removes
    # the sustained/DC component of the flux — WITHOUT this, continuous energy
    # (distorted guitar, pads) dominates the circular mean and collapses R even
    # where a clear beat exists. Validated on a synthetic click train: a DC
    # floor takes R 0.31→0.02; this HP restores it to 0.89.
    df = _highpass_rectify(env, max(1, int(0.12 * fps)))
    return df, fps


def _highpass_rectify(env, win):
    """Subtract a centered moving average (window `win`), half-wave rectify."""
    n = len(env)
    if n == 0:
        return env
    pre = [0.0] * (n + 1)
    for i in range(n):
        pre[i + 1] = pre[i] + env[i]
    half = win // 2
    out = [0.0] * n
    for k in range(n):
        a = max(0, k - half)
        b = min(n, k + half + 1)
        mean = (pre[b] - pre[a]) / (b - a)
        d = env[k] - mean
        out[k] = d if d > 0.0 else 0.0
    return out


def median(xs):
    if not xs:
        return float("nan")
    s = sorted(xs)
    n = len(s)
    m = n // 2
    return s[m] if n % 2 else 0.5 * (s[m - 1] + s[m])


def mad(xs):
    if not xs:
        return float("nan")
    md = median(xs)
    return median([abs(x - md) for x in xs])


def first_note_time(mono, sr):
    """First moment sound begins (silence→signal). The downbeat anchor: music
    starts on the one, and silence→signal is the single cleanest event in the
    whole take to detect — far more reliable than the first STRONG hit, which
    lands bars late on a quiet/building intro. Returns (time_s, threshold, floor)."""
    H = HOP
    n = len(mono) // H
    fps = sr / H
    rms = [0.0] * n
    for k in range(n):
        s = 0.0
        b = k * H
        for j in range(H):
            v = mono[b + j]
            s += v * v
        rms[k] = (s / H) ** 0.5
    lead = sorted(rms[:int(0.6 * fps)])[:max(1, int(0.12 * fps))]
    floor = sum(lead) / len(lead) if lead else 0.0
    thr = max(0.0015, 6.0 * floor)
    for k in range(1, n - 2):
        if rms[k] > thr and rms[k + 1] > thr and rms[k + 2] > thr:
            return k / fps, thr, floor
    return 0.0, thr, floor


def pick_peaks(env, fps, min_sep_s=0.12, k_mad=3.0):
    """Local maxima above an adaptive (median + k*MAD) threshold."""
    md = median(env)
    m = mad(env) or 1e-9
    thr = md + k_mad * m
    min_sep = max(1, int(min_sep_s * fps))
    peaks = []
    for i in range(1, len(env) - 1):
        if env[i] > thr and env[i] >= env[i - 1] and env[i] > env[i + 1]:
            if peaks and i - peaks[-1][0] < min_sep:
                if env[i] > env[peaks[-1][0]]:
                    peaks[-1] = (i, env[i])      # keep the stronger of two close peaks
                continue
            peaks.append((i, env[i]))
    return [(i / fps, v) for i, v in peaks]      # (time_s, strength)


# ---------------------------------------------------------------------------
# Autocorrelation tempo of the onset envelope
# ---------------------------------------------------------------------------

def autocorr_bpm(env, fps, bpm_lo=55.0, bpm_hi=200.0):
    """Dominant BPM from the onset envelope autocorrelation (with octave note)."""
    lag_lo = int(fps * 60.0 / bpm_hi)
    lag_hi = int(fps * 60.0 / bpm_lo)
    best_lag, best_val = lag_lo, -1.0
    ac = {}
    for lag in range(lag_lo, lag_hi + 1):
        s = 0.0
        for k in range(len(env) - lag):
            s += env[k] * env[k + lag]
        ac[lag] = s
        if s > best_val:
            best_val, best_lag = s, lag
    bpm = 60.0 * fps / best_lag
    return bpm, best_val, ac


# ---------------------------------------------------------------------------
# features.csv loading + per-track segmentation
# ---------------------------------------------------------------------------

def fget(r, k):
    try:
        return float(r[k])
    except (KeyError, ValueError, TypeError):
        return None


def load_segments(features_path):
    rows = list(csv.DictReader(open(features_path, newline="")))
    segs, cur, prev = [], [], None
    for r in rows:
        te = fget(r, "track_elapsed_s")
        if te is None:
            cur.append(r)
            continue
        if prev is not None and te < prev - 0.5:
            if cur:
                segs.append(cur)
            cur = []
        cur.append(r)
        prev = te
    if cur:
        segs.append(cur)
    return segs


def raw_tap_wallclock(session_dir):
    """Parse 'raw tap capture started ... wallclock=NNN' from session.log."""
    log = os.path.join(session_dir, "session.log")
    if not os.path.exists(log):
        return None
    for line in open(log):
        m = re.search(r"raw tap capture started.*wallclock=([\d.]+)", line)
        if m:
            return float(m.group(1))
    return None


def grid_beats_from_segment(seg, wc0):
    """Reconstruct grid beat instants (in raw-tap time) + pure-grid metronome.

    Returns (corrected_beats, pure_beats, grid_bpm, drift_series).
      corrected_beats: times (raw-tap s) where logged beatPhase01 wraps 1->0
                       (= what the preset actually saw, drift correction baked in)
      pure_beats:      fixed metronome at grid_bpm anchored on the first
                       corrected beat where |drift_ms| is small (~ pure cached grid)
      drift_series:    list of (raw_tap_time, drift_ms)
    """
    def rtt(r):
        wc = fget(r, "wallclock_s")
        return (wc - wc0) if (wc is not None and wc0 is not None) else fget(r, "track_elapsed_s")

    grid_bpm = None
    for r in seg:
        b = fget(r, "grid_bpm")
        if b:
            grid_bpm = b
            break

    corrected = []
    prev_ph, prev_t = None, None
    for r in seg:
        ph = fget(r, "beatPhase01")
        t = rtt(r)
        if ph is None or t is None:
            continue
        if prev_ph is not None and ph < prev_ph - 0.3:          # wrap 1->0 = a beat
            # linear-interpolate the crossing time of phase==1.0
            frac = (1.0 - prev_ph) / ((1.0 - prev_ph) + ph) if ((1.0 - prev_ph) + ph) > 0 else 0.0
            corrected.append(prev_t + frac * (t - prev_t))
        prev_ph, prev_t = ph, t

    drift_series = [(rtt(r), fget(r, "drift_ms")) for r in seg
                    if rtt(r) is not None and fget(r, "drift_ms") is not None]

    # pure metronome anchored on the earliest corrected beat with small drift
    pure = []
    if corrected and grid_bpm:
        period = 60.0 / grid_bpm
        anchor = corrected[0]
        # prefer an anchor near a low-drift frame
        for t in corrected:
            d = min((abs(dm) for (tt, dm) in drift_series if abs(tt - t) < 0.2), default=999)
            if d < 15.0:
                anchor = t
                break
        # extend metronome across the whole window
        span_lo = (corrected[0] - 2.0)
        span_hi = (corrected[-1] + 2.0)
        n0 = math.floor((span_lo - anchor) / period)
        n1 = math.ceil((span_hi - anchor) / period)
        pure = [anchor + n * period for n in range(n0, n1 + 1)]
    return corrected, pure, grid_bpm, drift_series


# ---------------------------------------------------------------------------
# Phase: circular phase-locking statistics of the onset envelope against the
# cached grid period. This is the standard way to measure beat-phase alignment:
#   - fold every frame's onset weight onto the grid's beat cycle (phase 0..2pi)
#   - R = |circular mean| in [0,1]  -> how concentrated onset energy is at ONE
#         phase of the beat cycle. R~0 = no beat at this tempo (energy smeared
#         across the cycle); R high = a clear beat locked to this period.
#   - offset = angle of the circular mean -> WHERE in the beat the energy peaks.
#         offset~0 ms = grid beat lands on the music's beat; nonzero = the grid
#         is off by a constant (exactly what a first-hit anchor corrects).
# R is rotation-invariant (independent of the beat0 anchor), so sweeping the
# period and watching R peak is also a clean tempo check.
# ---------------------------------------------------------------------------

def phase_lock(env, fps, t_lo, t_hi, beat0, period):
    """Return (R, offset_ms) for onset energy folded onto a beat cycle of `period`."""
    C = S = W = 0.0
    k_lo = max(0, int(t_lo * fps))
    k_hi = min(len(env), int(t_hi * fps))
    twopi = 2.0 * math.pi
    for k in range(k_lo, k_hi):
        w = env[k]
        if w <= 0.0:
            continue
        t = k / fps
        frac = ((t - beat0) / period) % 1.0
        ph = twopi * frac
        C += w * math.cos(ph)
        S += w * math.sin(ph)
        W += w
    if W <= 0.0:
        return 0.0, float("nan")
    R = math.hypot(C, S) / W
    ang = math.atan2(S, C) / twopi          # in [-0.5, 0.5] turns
    if ang > 0.5:
        ang -= 1.0
    return R, ang * period * 1000.0


def dominant_pulse(env, fps, t_lo, t_hi, beat0, bpm_lo=50.0, bpm_hi=240.0, step_bpm=0.5):
    """Sweep tempo over a WIDE absolute range; return the period of strongest
    phase-lock. This is the audio's *actual* dominant pulse and clarity — the
    detector self-check (a clear beat ⇒ high R somewhere) and the ground-truth
    tempo to compare the grid against. Returns (bpm_at_maxR, R_max, off_ms_at_max)."""
    best = (bpm_lo, -1.0, float("nan"))
    bpm = bpm_lo
    while bpm <= bpm_hi:
        R, off = phase_lock(env, fps, t_lo, t_hi, beat0, 60.0 / bpm)
        if R > best[1]:
            best = (bpm, R, off)
        bpm += step_bpm
    return best


# ---------------------------------------------------------------------------
# Report for one track
# ---------------------------------------------------------------------------

def analyse(session_dir, track_index, label):
    feats = os.path.join(session_dir, "features.csv")
    wav = os.path.join(session_dir, "raw_tap.wav")
    segs = load_segments(feats)
    if track_index >= len(segs):
        print(f"  track-index {track_index} out of range ({len(segs)} segments)")
        return
    seg = segs[track_index]
    wc0 = raw_tap_wallclock(session_dir)
    corrected, pure, grid_bpm, drift = grid_beats_from_segment(seg, wc0)
    has_pcm = os.path.exists(wav) and track_index == 0   # raw_tap = first track only

    # Segment's true span in raw-tap time (so a 30 s tap that bled into the
    # next track is clipped to THIS track only).
    seg_t0 = drift[0][0] if drift else 0.0
    seg_t1 = drift[-1][0] if drift else 0.0

    print(f"\n{'='*86}\n{label}   session={os.path.basename(os.path.normpath(session_dir))}  seg#{track_index}")
    print(f"  cached grid: bpm={grid_bpm:.1f}  period={60.0/grid_bpm*1000:.1f} ms   "
          f"features span={seg_t0:.1f}..{seg_t1:.1f}s")

    # WANDER (always available, from features.csv)
    if drift:
        d0 = drift[0][1]
        dvals = [d for (_t, d) in drift]

        def near(ts):
            cand = [d for (t, d) in drift if abs(t - ts) < 1.0]
            return cand[len(cand) // 2] if cand else None
        d10, d30 = near(10.0), near(30.0)
        print(f"  LIVE-TRACKER WANDER (drift_ms): start={d0:+.0f}  ~10s={('%+.0f'%d10) if d10 is not None else 'n/a'}  "
              f"~30s={('%+.0f'%d30) if d30 is not None else 'n/a'}  "
              f"range=[{min(dvals):+.0f},{max(dvals):+.0f}]  total span={max(dvals)-min(dvals):.0f} ms")

    if not has_pcm:
        print("  (no PCM for this track — raw_tap.wav covers the session's first track only;")
        print("   grid/onset comparison skipped here. WANDER above is from features.csv.)")
        return

    mono, sr = read_wav_mono(wav)
    dur = len(mono) / sr
    env, fps = onset_envelope(mono, sr)
    # Clip the analysis window to where THIS track actually plays in the tap.
    t_lo = max(0.0, seg_t0)
    t_hi = min(dur, seg_t1 if seg_t1 > seg_t0 + 1 else dur)
    beat0 = pure[0] if pure else (corrected[0] if corrected else 0.0)
    period = 60.0 / grid_bpm

    # Per-second onset energy → structure + beat-entry detection.
    nsec = int(t_hi - t_lo)
    sec_energy = []
    for s in range(nsec):
        a = int((t_lo + s) * fps)
        b = int((t_lo + s + 1) * fps)
        sec_energy.append(sum(env[a:b]))
    emax = max(sec_energy) if sec_energy else 1.0
    # beat-entry = first second whose energy exceeds 40% of the track's max and
    # stays high — i.e. percussion/full-band rhythm has arrived.
    entry = 0
    for s in range(nsec):
        if sec_energy[s] > 0.40 * emax:
            entry = s
            break
    bars = "".join("█" if e > 0.66 * emax else ("▄" if e > 0.40 * emax else ("·" if e > 0.15 * emax else " "))
                   for e in sec_energy)
    print(f"  onset-energy/s [{t_lo:.0f}–{t_hi:.0f}s]: |{bars}|  (beat/rhythm enters ≈ {entry}s)")

    # Phase-lock measured ONLY where a beat is present (entry → end).
    b_lo, b_hi = t_lo + entry, t_hi
    if b_hi - b_lo < 4.0:
        b_lo = t_lo  # too short — fall back to whole window

    # Thresholds recalibrated for REAL music: an autocorr-confirmed rock beat
    # sits at R≈0.25 (lots of off-beat 8th/16th onset content is normal).
    def lock_word(r):
        return "STRONG" if r >= 0.35 else ("moderate" if r >= 0.22 else ("weak" if r >= 0.14 else "none"))

    k_lo = max(0, min(len(env), int(b_lo * fps)))
    k_hi = max(0, min(len(env), int(b_hi * fps)))
    reg = env[k_lo:k_hi]

    # TEMPO — autocorrelation of the onset function (decisive; robust to the
    # off-beat content that keeps the circular R modest). Fold octaves to grid.
    ac_bpm, _ac_strength, _ac = autocorr_bpm(reg, fps, 60.0, 200.0)
    ac_fold = min([ac_bpm, ac_bpm * 2, ac_bpm / 2, ac_bpm * 3, ac_bpm / 3],
                  key=lambda b: abs(b - grid_bpm))
    tempo_err = 100.0 * abs(ac_fold - grid_bpm) / grid_bpm

    # PHASE — circular offset at the GRID period (the Q1 phase number) and, as a
    # lock-existence confirmation, at the audio's OWN autocorr beat period.
    R, off_ms = phase_lock(env, fps, b_lo, b_hi, beat0, period)
    R_audio, off_audio = phase_lock(env, fps, b_lo, b_hi, beat0, 60.0 / ac_fold)

    print(f"  beat-present region {b_lo:.0f}–{b_hi:.0f}s ({b_hi-b_lo:.0f}s):")
    print(f"    TEMPO (autocorrelation): grid={grid_bpm:.1f}  audio-beat={ac_bpm:.1f} "
          f"(octave→{ac_fold:.1f})  → err={tempo_err:.1f}%")
    print(f"    PHASE-LOCK: R={R:.2f} [{lock_word(R)}] at grid period   "
          f"(audio's own {ac_fold:.0f}-bpm beat: R={R_audio:.2f} [{lock_word(R_audio)}])")
    print(f"    GRID-PHASE-ERROR = {off_ms:+.0f} ms  ← the constant a first-hit anchor removes")

    # Windowed phase-lock — short windows avoid the long-window phase-slip that
    # tiny tempo errors cause. Constant offset across windows = anchorable phase
    # error; drifting offset = grid tempo slightly off. R per window = local
    # lock strength (more meaningful than the slip-washed global R).
    wins = []
    ws, step, t = 5.0, 2.5, b_lo
    while t + ws <= b_hi + 1e-6:
        rw, ow = phase_lock(env, fps, t, t + ws, beat0, period)
        wins.append((t, rw, ow))
        t += step
    good = [(rw, ow) for (_t, rw, ow) in wins if rw >= 0.15]
    if good:
        offs = sorted(ow for (_r, ow) in good)
        wmed = offs[len(offs) // 2]
        rmean = sum(r for r, _ in good) / len(good)
        ospread = max(offs) - min(offs)
        print(f"    windowed phase (5s): {len(good)}/{len(wins)} windows beat-present  "
              f"mean R={rmean:.2f}  offset median={wmed:+.0f} ms  spread={ospread:.0f} ms")
    if wins:
        print("      " + " ".join(f"[{t:.0f}s R{rw:.2f} {ow:+.0f}]" for (t, rw, ow) in wins))

    # Q2 — ANCHOR. The first NOTE (silence→sound) is the downbeat anchor: music
    # starts on the one. The first STRONG hit is reported ONLY as the rejected
    # contrast — on a quiet/building intro it lands bars (or here, seconds) late.
    fn_t, _thr, _floor = first_note_time(mono, sr)
    win_peaks = [(t, v) for (t, v) in pick_peaks(env, fps) if t_lo <= t <= t_hi]
    fh_t = None
    if win_peaks:
        vmax = max(v for _t, v in win_peaks)
        fh_t = next((t for (t, v) in win_peaks if v > 0.40 * vmax), win_peaks[0][0])
    # alignment of onsets to a pulse anchored at the first note (at grid tempo)
    wins, t = [], max(t_lo, fn_t + 0.2)
    while t + 5.0 <= t_hi + 1e-6:
        rw, ow = phase_lock(env, fps, t, t + 5.0, fn_t, period)
        wins.append((rw, ow))
        t += 2.5
    g = sorted(o for (r, o) in wins if r >= 0.15)
    contrast = f"   (first STRONG hit would be t={fh_t:.2f}s, Δ{fh_t-fn_t:+.1f}s — REJECTED)" if fh_t is not None else ""
    print(f"  FIRST-NOTE ANCHOR: sound begins t={fn_t:.2f}s (clean silence→signal){contrast}")
    if g:
        print(f"    pulse anchored at the first note, grid tempo: onsets land "
              f"{g[len(g)//2]:+.0f} ms off  (spread {max(g)-min(g):.0f} ms, {len(g)} windows)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir")
    ap.add_argument("--track-index", type=int, default=0)
    ap.add_argument("--label", default="track")
    a = ap.parse_args()
    analyse(a.session_dir, a.track_index, a.label)


if __name__ == "__main__":
    main()
