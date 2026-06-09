#!/usr/bin/env python3
"""AGC3.6 — Validate / tune the cold-start peak floor on REAL session audio (BUG-029 re-open).

The first AGC3 fix (seed-from-first-audible) shipped green on a synthetic test and FAILED the
2026-06-09 M7, because the synthetic test used the wrong onset SHAPE (silence→immediately-loud).
Real tracks open silence → QUIET intro → loud hit, and the loud hit inflates `f.bass` while the AGC
is still converged on the quiet intro. Through Ferrofluid Ocean's `1.0 + 0.8·clamp(f.bass,0,1)` that
holds the spikes at max height for ~0.8 s — the visible lurch.

This tool replays a session's `raw_tap.wav` through a faithful replica of `BandEnergyProcessor`'s AGC
(the AGC is SCALE-INVARIANT, so the replica's f.bass matches production regardless of FFT scale) with
and without the cold-start peak floor, and sweeps `peakFraction` so the value can be tuned against the
ACTUAL audio that failed — not synthetic (Failed Approach #27). Pure stdlib (manual IEEE-float WAV
read + recursive FFT); no numpy.

Usage:
    python3 validate_coldstart_floor.py <session_dir> [--seconds 4] [--window-s 2.5]

Reports, for the first `--seconds`: the no-floor f.bass trajectory (and how many frames pin > 1.0 =
FFO max-lock), and a peakFraction sweep of the first-loud-hit f.bass.
"""
import argparse
import cmath
import math
import os
import struct


def read_float_wav(path):
    """Read an IEEE-float (or int16) WAV with the stdlib (the `wave` module rejects float WAVs)."""
    with open(path, "rb") as f:
        b = f.read()
    i, sr, ch, bits, data = 12, 44100, 2, 32, b""
    while i < len(b) - 8:
        cid = b[i:i + 4]
        sz = struct.unpack("<I", b[i + 4:i + 8])[0]
        if cid == b"fmt ":
            _, ch, sr = struct.unpack("<HHI", b[i + 8:i + 16])
            bits = struct.unpack("<H", b[i + 22:i + 24])[0]
        elif cid == b"data":
            data = b[i + 8:i + 8 + sz]
            break
        i += 8 + sz + (sz & 1)
    if bits == 32:
        flo = struct.unpack("<" + str(len(data) // 4) + "f", data)
    else:
        flo = [v / 32768.0 for v in struct.unpack("<" + str(len(data) // 2) + "h", data)]
    mono = [sum(flo[k * ch:(k + 1) * ch]) / ch for k in range(len(flo) // ch)]
    return sr, mono


def fft(a):
    n = len(a)
    if n <= 1:
        return a
    ev, od = fft(a[0::2]), fft(a[1::2])
    out = [0] * n
    for k in range(n // 2):
        t = cmath.exp(-2j * cmath.pi * k / n) * od[k]
        out[k], out[k + n // 2] = ev[k] + t, ev[k] - t
    return out


def band_frames(mono, sr, seconds, fft_n=1024, hop=4096):
    """Per-frame (time, bass-RMS, total-6-band-RMS) — the inputs the AGC sees."""
    binres = sr / fft_n
    win = [0.5 - 0.5 * math.cos(2 * math.pi * k / (fft_n - 1)) for k in range(fft_n)]

    def bins(lo, hi):
        return (max(0, int(lo / binres)), min(fft_n // 2, int(math.ceil(hi / binres))))

    bass = bins(20, 250)
    b6 = [bins(lo, hi) for lo, hi in [(20, 80), (80, 250), (250, 1000),
                                      (1000, 4000), (4000, 8000), (8000, sr // 2)]]
    out, n = [], len(mono)
    for s in range(0, min(n - fft_n, int(sr * seconds)), hop):
        mags = [abs(x) for x in fft([mono[s + k] * win[k] for k in range(fft_n)])[:fft_n // 2]]
        rms = lambda lo, hi: math.sqrt(sum(mags[j] ** 2 for j in range(lo, hi)) / max(1, hi - lo))
        out.append((s / sr, rms(*bass), sum(rms(lo, hi) for lo, hi in b6)))
    return out


def run_agc(frames, sr, hop, peak_fraction, window_s):
    """Replica of BandEnergyProcessor's AGC (seed-from-first-audible + hold + optional cold-start
    peak floor). peak_fraction=None disables the floor (the pre-AGC3.6 / D-148 behaviour)."""
    agc, silent_run, cs_frames, cs_peak, sm = 0.0, 0, -1, 0.0, 0.0
    sm_rate = 0.65 ** 0.5  # bass instant smoother @ ~the production rate
    out, fc = [], 0
    win_frames = window_s * (sr / hop)
    for t, raw_bass, tot in frames:
        rate = 0.95 if fc < 60 else 0.992
        was_unseeded, was_sustained = (agc == 0), (silent_run >= 30)
        near_silent = (agc != 0 and tot < 0.02 * agc)
        silent_run = silent_run + 1 if near_silent else 0
        if agc == 0:
            if tot > 0:
                agc = tot
        elif near_silent and silent_run >= 30:
            pass
        else:
            agc = rate * agc + (1 - rate) * tot
        eff = agc
        if peak_fraction is not None:
            if tot > 0 and (was_unseeded or was_sustained):
                cs_frames, cs_peak = 0, tot
            if cs_frames >= 0:
                cs_peak = max(cs_peak, tot)
                eff = max(agc, peak_fraction * cs_peak)
                if tot > 0:
                    cs_frames += 1
                if cs_frames >= win_frames:
                    cs_frames = -1
        scale = 0.5 / eff if eff > 1e-10 else 0
        sm = sm_rate * sm + (1 - sm_rate) * (raw_bass * scale)
        out.append((t, sm))
        fc += 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("session_dir")
    ap.add_argument("--seconds", type=float, default=4.0)
    ap.add_argument("--window-s", type=float, default=2.5)
    ap.add_argument("--hop", type=int, default=4096)
    a = ap.parse_args()
    wav = os.path.join(a.session_dir, "raw_tap.wav")
    if not os.path.exists(wav):
        print(f"no raw_tap.wav in {a.session_dir}")
        return
    sr, mono = read_float_wav(wav)
    frames = band_frames(mono, sr, a.seconds, hop=a.hop)
    print(f"raw_tap.wav: sr={sr}  dur~{a.seconds}s  frames={len(frames)}  window={a.window_s}s\n")

    base = run_agc(frames, sr, a.hop, None, a.window_s)
    nolock = sum(1 for _, v in base if v > 1.0)
    print(f"NO floor (D-148):   peak f.bass={max(v for _, v in base):.3f}   "
          f"frames pinned > 1.0 (FFO max-lock) = {nolock}")
    print(f"\n  {'peakFraction':>12} {'1st-hit f.bass':>14} {'FFO max-lock frames':>20}")
    for pf in [0.20, 0.25, 0.30, 0.35, 0.45, 0.60]:
        out = run_agc(frames, sr, a.hop, pf, a.window_s)
        hit = max(v for t, v in out if 0.6 < t < 2.2)
        lock = sum(1 for _, v in out if v > 1.0)
        note = "  <- ~max" if hit > 0.95 else ("  <- muted" if hit < 0.45 else "")
        print(f"  {pf:>12.2f} {hit:>14.3f} {lock:>20}{note}")


if __name__ == "__main__":
    main()
