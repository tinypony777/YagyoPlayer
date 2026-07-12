"""Python mirror of KitsunebiAnalyzerEngine — validates the algorithm and
generates expected constants for the Swift unit tests."""
import numpy as np

# ---------- K-weighting (BS.1770-4) ----------

def stage1(sr):
    if sr == 48000:
        return [1.53512485958697, -2.69169618940638, 1.19839281085285,
                -1.69065929318241, 0.73248077421585]
    f, gdb, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    A = 10 ** (gdb / 40)
    w0 = 2 * np.pi * f / sr
    alpha = np.sin(w0) / (2 * q)
    c, sA = np.cos(w0), np.sqrt(A)
    t = 2 * sA * alpha
    b0 = A * ((A + 1) + (A - 1) * c + t)
    b1 = -2 * A * ((A - 1) + (A + 1) * c)
    b2 = A * ((A + 1) + (A - 1) * c - t)
    a0 = (A + 1) - (A - 1) * c + t
    a1 = 2 * ((A - 1) - (A + 1) * c)
    a2 = (A + 1) - (A - 1) * c - t
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]

def stage2(sr):
    if sr == 48000:
        return [1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621]
    f = 38.13547087602444
    w0 = 2 * np.pi * f / sr
    alpha = np.sin(w0) / (2 * 0.7071067811865476)
    c = np.cos(w0)
    b0 = (1 + c) / 2
    b1 = -(1 + c)
    b2 = (1 + c) / 2
    a0 = 1 + alpha
    a1 = -2 * c
    a2 = 1 - alpha
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]

def biquad(x, k):
    """y[n] = b0x+b1x1+b2x2 - a1y1 - a2y2 (zero initial state)."""
    b0, b1, b2, a1, a2 = k
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        y[i] = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x[i]
        y2, y1 = y1, y[i]
    return y

# ---------- True peak FIR (float32 to match Swift constants) ----------

def make_fir(taps=48, factor=4):
    cutoff = np.float32(1.0 / factor)
    gain = np.float32(factor)
    center = np.float32(taps - 1) / 2
    a = [np.float32(v) for v in (0.35875, 0.48829, 0.14128, 0.01168)]
    co = np.zeros(taps, dtype=np.float32)
    for i in range(taps):
        n = np.float32(i) - center
        sinc = cutoff if abs(n) < 1e-6 else np.float32(
            np.sin(np.pi * cutoff * n) / (np.pi * n))
        ph = np.float32(2 * np.pi * i / (taps - 1))
        w = a[0] - a[1] * np.cos(ph) + a[2] * np.cos(2 * ph) - a[3] * np.cos(3 * ph)
        co[i] = sinc * w * gain
    for p in range(factor):
        g = co[p::factor].sum(dtype=np.float32)
        if abs(g) > 1e-8:
            co[p::factor] = (co[p::factor] / g).astype(np.float32)
    return co

def true_peak_db(channels, factor=4):
    fir = make_fir().astype(np.float64)
    peak = 0.0
    for ch in channels:
        up = np.zeros(len(ch) * factor)
        up[::factor] = ch
        conv = np.convolve(up, fir, mode="full")
        peak = max(peak, np.abs(conv).max())
    return 20 * np.log10(peak) if peak > 0 else None

# ---------- Engine mirror ----------

def analyze(channels, sr):
    channels = [np.asarray(c, dtype=np.float64) for c in channels]
    ch_count = len(channels)
    n = len(channels[0])
    hop = max(1, int(sr * 0.1))

    # K-weighting + weighted power sum
    weights = [1.0] * ch_count if ch_count <= 2 else [
        0.0 if c == 3 else (1.41 if c in (4, 5) else 1.0) for c in range(ch_count)]
    k1, k2 = stage1(sr), stage2(sr)
    power = np.zeros(n)
    for c, ch in enumerate(channels):
        f = biquad(biquad(ch, k1), k2)
        power += weights[c] * f * f

    # hops -> 400ms blocks + 3s short-term
    hops = [power[i:i + hop].sum() / hop for i in range(0, n - hop + 1, hop)]
    def ldb(ms):
        return -0.691 + 10 * np.log10(ms) if ms > 0 else -np.inf
    blocks = [ldb(np.mean(hops[i - 3:i + 1])) for i in range(3, len(hops))]
    shorts = [ldb(np.mean(hops[i - 29:i + 1])) for i in range(29, len(hops))]
    max_short = max(shorts) if shorts else None

    # gating
    def power_mean_db(vals):
        return 10 * np.log10(np.mean([10 ** (v / 10) for v in vals]))
    abs_gated = [b for b in blocks if np.isfinite(b) and b > -70]
    integrated = None
    if abs_gated:
        rel = power_mean_db(abs_gated) - 10
        rel_gated = [b for b in abs_gated if b > rel]
        if rel_gated:
            integrated = power_mean_db(rel_gated)

    # peaks / clips / correlation
    sample_peak = max(np.abs(ch).max() for ch in channels)
    sample_peak_db = 20 * np.log10(sample_peak) if sample_peak > 0 else None
    tp_db = true_peak_db(channels)
    clip_runs = 0
    positions = []
    for ch in channels:
        mask = np.abs(ch) >= 0.999
        run = 0
        start = 0
        for i, m in enumerate(mask):
            if m:
                if run == 0:
                    start = i
                run += 1
            elif run:
                if run >= 3:
                    clip_runs += 1
                    positions.append(start / sr)
                run = 0
        if run >= 3:
            clip_runs += 1
            positions.append(start / sr)
    corr = None
    if ch_count >= 2:
        l, r = channels[0], channels[1]
        den = np.sqrt((l * l).sum() * (r * r).sum())
        corr = float((l * r).sum() / den) if den > 0 else 1.0

    return dict(integrated=integrated, max_short=max_short,
                sample_peak_db=sample_peak_db, true_peak_db=tp_db,
                clip_runs=clip_runs, corr=corr,
                max_short_finite=max_short if max_short is None or np.isfinite(max_short) else None)

# ---------- Test signals ----------

SR = 48000

def sine(freq, amp, seconds, phase=0.0):
    t = np.arange(int(SR * seconds))
    return amp * np.sin(2 * np.pi * freq * t / SR + phase)

print("=== T1: stereo 997Hz sine amp0.1 10s ===")
s = sine(997, 0.1, 10.0)
r = analyze([s, s.copy()], SR)
print({k: v for k, v in r.items()})

print("=== T3: mono full-scale 1kHz square 1s ===")
t = np.arange(SR)
sq = np.where(np.sin(2 * np.pi * 1000 * t / SR + 1e-9) >= 0, 1.0, -1.0)
r3 = analyze([sq], SR)
print({k: v for k, v in r3.items()})

print("=== T4: anti-phase stereo 997Hz amp0.5 5s ===")
a = sine(997, 0.5, 5.0)
r4 = analyze([a, -a], SR)
print({k: v for k, v in r4.items()})

print("=== T5: mono fs/4 sine phase pi/4 amp0.5 1s ===")
t = np.arange(SR)
x5 = 0.5 * np.sin(2 * np.pi * (SR / 4) * t / SR + np.pi / 4)
r5 = analyze([x5], SR)
print({k: v for k, v in r5.items()})

print("=== K-weighting gain check at 997Hz/48k (both stages) ===")
import numpy.polynomial as _np
def gain_at(k, f, sr):
    b = np.array(k[:3]); a = np.array([1.0, k[3], k[4]])
    z = np.exp(2j * np.pi * f / sr)
    return abs(np.polyval(b[::-1], 1/z) / np.polyval(a[::-1], 1/z))
g = gain_at(stage1(SR), 997, SR) * gain_at(stage2(SR), 997, SR)
print("K-gain@997Hz:", 20*np.log10(g), "dB")
