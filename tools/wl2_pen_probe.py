#!/usr/bin/env python3
"""wl2_pen_probe.py — WL.2-a pre-check for Witchlight's pen kinematics.

Runs the CPU half of `docs/presets/WITCHLIGHT_DESIGN.md` §3.1 against recorded
sessions and rasterises the resulting 30-second stroke, to answer one question
before any shader exists: DOES THE FIGURE READ AS A DRAWING?

Two heading models, so the falsification stays reproducible:

  absolute   theta_dot = clamp(k * d/dt phi_bar, +/-omega_max)      <- §3.1 as
             ... which integrates to theta = k*phi_bar + c, i.e. the heading IS
             the smoothed phase. `tonal_phase_fifths` is strongly CONCENTRATED
             on real music (mean resultant length up to 0.98 once smoothed), so
             the pen hovers near one direction and draws a near-straight line.
             This is an absolute read of a bounded circular primitive — the same
             shape as Failed Approach #31.

  deviation  theta_dot = clamp(k * wrap(phi_fast - phi_slow), +/-omega_max)
             The excursion from the phase's own slow circular mean (D-026
             applied to a circular quantity). Produces legible figures on all
             four captures. Adopted; see docs/diagnostics/WL2A_PEN_KINEMATICS_2026-07-31.md.

This models the CPU kinematics ONLY. It says nothing about how beads render or
how the figure moves — those need the Metal look-spike and Scripts/motion_gate.sh
(stills hid the Truchet Loom jitter, D-194).

Usage:
    tools/wl2_pen_probe.py OUTDIR [--sessions DIR] [--captures a,b,c] [--seconds 30]

Writes <capture>_<model>.ppm per capture and prints the metrics table.
Deps: python3 stdlib only (convert PPMs with ffmpeg if you want PNGs).
"""

import argparse
import colorsys
import csv
import math
import os
import sys

# --- §3.1 constants (keep in sync with WITCHLIGHT_DESIGN.md) ------------------
W, H       = 960, 540      # 16:9 raster
R_MIN      = 0.08          # min turning radius, fraction of frame height (§3.1b)
V0         = 0.12          # base pen speed, frame-heights / s
OMEGA_MAX  = V0 / R_MIN    # = 1.5 rad/s
TAU_FAST   = 0.8           # circular EMA (fast), s
TAU_SLOW   = 8.0           # circular EMA (slow) — the deviation pivot, s
EMIT_HZ    = 34.0          # bead emission, fixed TIME rate (§3.2)
TRAIL_S    = 30.0          # trail window (§3.3)
RELAX_FULL = 1.0           # full relaxation weight below this age, s (§3.1c)
RELAX_ZERO = 4.0           # zero relaxation weight above this age, s
RELAX_K    = 0.30          # per-frame pull toward neighbour midpoint
SPEED_MOD  = 0.25          # arousal modulation of pen speed, +/- fraction


def wrap(d):
    """Wrap an angle difference to (-pi, pi]."""
    return (d + math.pi) % (2 * math.pi) - math.pi


def pct(xs, q):
    s = sorted(xs)
    return s[min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))]


def load(session_dir, capture, seconds):
    """Read wallclock / tonal_phase_fifths / arousal from a recorded session."""
    path = os.path.join(session_dir, capture, "features.csv")
    t, phi, arousal = [], [], []
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            try:
                ti = float(row["wallclock_s"])
                if seconds and t and ti - t[0] > seconds:
                    break
                t.append(ti)
                phi.append(float(row["tonal_phase_fifths"]))
                arousal.append(float(row["arousal"]))
            except (ValueError, KeyError):
                continue
    if not t:
        raise SystemExit(f"wl2_pen_probe: no usable rows in {path}")
    return t, phi, arousal


def circular_ema(t, phi, tau):
    """EMA sin/cos separately, recombine via atan2 (CR.1.2 / D-198).

    Never EMA the raw +/-pi sawtooth — it averages across the wrap.
    """
    c, s = math.cos(phi[0]), math.sin(phi[0])
    out, prev = [], t[0]
    for ti, v in zip(t, phi):
        dt = max(1e-4, ti - prev)
        prev = ti
        a = 1.0 - math.exp(-dt / tau)
        c += a * (math.cos(v) - c)
        s += a * (math.sin(v) - s)
        out.append(math.atan2(s, c))
    return out


def steer(t, phi, model):
    """Per-frame steering signal (rad/s) plus the hue phase, per heading model."""
    fast = circular_ema(t, phi, TAU_FAST)
    if model == "absolute":
        rate = [0.0] + [
            wrap(b - a) / max(1e-4, tb - ta)
            for a, b, ta, tb in zip(fast, fast[1:], t, t[1:])
        ]
        return rate, fast
    slow = circular_ema(t, phi, TAU_SLOW)
    return [wrap(f - s) for f, s in zip(fast, slow)], fast


def run(t, phi, arousal, model):
    """Integrate the pen and return (beads, clamped_fraction, heading_turns)."""
    signal, hue_phase = steer(t, phi, model)
    p95 = pct([abs(x) for x in signal], 0.95) or 1e-6
    k = (0.85 * OMEGA_MAX) / p95          # per-track normalised steering gain

    a_lo, a_hi = min(arousal), max(arousal)
    span = max(1e-6, a_hi - a_lo)

    theta = x = y = 0.0
    beads = []                             # [x, y, age, hue01]
    clamped = steps = 0
    travel = since_emit = 0.0
    prev = t[0]
    emit_dt = 1.0 / EMIT_HZ

    for ti, sig, ar, hp in zip(t, signal, arousal, hue_phase):
        dt = max(1e-4, ti - prev)
        prev = ti

        raw = k * sig
        omega = max(-OMEGA_MAX, min(OMEGA_MAX, raw))
        if abs(raw) > OMEGA_MAX:
            clamped += 1
        steps += 1
        theta += omega * dt
        travel += abs(omega) * dt

        v = V0 * (1.0 + SPEED_MOD * (2.0 * (ar - a_lo) / span - 1.0))
        x += v * math.cos(theta) * dt
        y += v * math.sin(theta) * dt

        since_emit += dt
        if since_emit >= emit_dt:
            since_emit = 0.0
            beads.append([x, y, 0.0, (hp + math.pi) / (2.0 * math.pi)])

        for b in beads:
            b[2] += dt
        while beads and beads[0][2] > TRAIL_S:
            beads.pop(0)

        # Age-weighted Laplacian relaxation (§3.1c): smooth the live end,
        # freeze the record past RELAX_ZERO.
        for i in range(1, len(beads) - 1):
            age = beads[i][2]
            if age >= RELAX_ZERO:
                break
            w = RELAX_K * (1.0 if age <= RELAX_FULL
                           else (RELAX_ZERO - age) / (RELAX_ZERO - RELAX_FULL))
            mx = 0.5 * (beads[i - 1][0] + beads[i + 1][0])
            my = 0.5 * (beads[i - 1][1] + beads[i + 1][1])
            beads[i][0] += w * (mx - beads[i][0])
            beads[i][1] += w * (my - beads[i][1])

    return beads, clamped / max(1, steps), travel / (2.0 * math.pi)


def raster(beads, path):
    """Additive-accumulate the stroke into a PPM. Flat colour, no shading —
    this probe answers a geometry question, not a fidelity one."""
    if not beads:
        return
    xs = [b[0] for b in beads]
    ys = [b[1] for b in beads]
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    extent = max(max(xs) - min(xs), max(ys) - min(ys), 1e-3)
    scale = 0.80 * H / extent
    buf = [[0.0, 0.0, 0.0] for _ in range(W * H)]

    def put(i, j, r, g, b):
        if 0 <= i < W and 0 <= j < H:
            p = buf[j * W + i]
            p[0] += r
            p[1] += g
            p[2] += b

    for idx, (bx, by, age, hue) in enumerate(beads):
        alpha = max(0.0, 1.0 - age / TRAIL_S) ** 1.6        # §3.3 falloff
        if alpha <= 0.0:
            continue
        r, g, bl = colorsys.hsv_to_rgb(hue % 1.0, 0.72, 1.0)
        i = int(W / 2 + (bx - cx) * scale)
        j = int(H / 2 - (by - cy) * scale)
        rad = max(1, int(2.6 * (1.0 - 0.65 * age / TRAIL_S)))
        for dj in range(-rad, rad + 1):
            for di in range(-rad, rad + 1):
                d2 = di * di + dj * dj
                if d2 <= rad * rad:
                    f = alpha * (1.0 - math.sqrt(d2) / (rad + 0.5))
                    put(i + di, j + dj, r * f, g * f, bl * f)
        if idx + 1 < len(beads):
            nx, ny = beads[idx + 1][0], beads[idx + 1][1]
            i2 = int(W / 2 + (nx - cx) * scale)
            j2 = int(H / 2 - (ny - cy) * scale)
            n = max(abs(i2 - i), abs(j2 - j), 1)
            for s in range(n):
                put(int(i + (i2 - i) * s / n), int(j + (j2 - j) * s / n),
                    r * alpha * 0.35, g * alpha * 0.35, bl * alpha * 0.35)

    with open(path, "wb") as fh:
        fh.write(b"P6\n%d %d\n255\n" % (W, H))
        fh.write(bytes(min(255, int(255 * (1.0 - math.exp(-1.7 * max(0.0, c)))))
                       for p in buf for c in p))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir")
    ap.add_argument("--sessions", default=os.path.expanduser("~/Documents/phosphene_sessions"))
    ap.add_argument("--captures", default="fixturegen-so_what,fixturegen-there_there,"
                                          "fixturegen-love_rehab,beat-match-test-session")
    ap.add_argument("--seconds", type=float, default=TRAIL_S)
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    print(f"{'capture':28}{'model':>11}{'clamp%':>9}{'headingTurns':>14}")
    for capture in args.captures.split(","):
        t, phi, arousal = load(args.sessions, capture, args.seconds)
        for model in ("absolute", "deviation"):
            beads, clamp_frac, turns = run(t, phi, arousal, model)
            raster(beads, os.path.join(args.outdir, f"{capture}_{model}.ppm"))
            print(f"{capture:28}{model:>11}{100 * clamp_frac:>8.1f}%{turns:>14.2f}")
    print(f"\nWrote PPMs to {args.outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
