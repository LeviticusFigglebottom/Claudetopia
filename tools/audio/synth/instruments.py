"""The Wickmere instrument set.

Every voice here is a physical or spectral model, never a sample: bells are inharmonic
additive/FM partials, strings are Karplus-Strong or bowed resonators, winds are noise through
resonant formants with breath, the choir is formant-filtered detuned saws, drums are modal
membranes. Each function returns a mono float array unless it says otherwise.

The bell is the game's voice (WORLD_BIBLE §1.1) and gets the most care: real bell partials
(hum, prime, tierce, quint, nominal and a stretched upper series) with per-partial decay so
the hum outlasts the strike by many seconds.
"""
from __future__ import annotations

import numpy as np
from scipy import signal

from . import env as envmod
from . import filters, fx, osc
from .core import SR, TWO_PI, midi_to_hz, samples


# =================================================================================================
# Bells
# =================================================================================================

# Ratios of a tuned church bell's partials to the nominal-derived strike note, with relative
# amplitudes and decay multipliers. The hum (0.5) rings longest; the strike partials die fast.
BELL_PARTIALS = [
    # (ratio, amplitude, t60 multiplier)
    (0.500, 0.85, 1.00),   # hum
    (1.000, 0.95, 0.72),   # prime / fundamental
    (1.183, 0.55, 0.55),   # tierce (minor third: a bell's sad colour)
    (1.506, 0.45, 0.45),   # quint
    (2.000, 0.80, 0.38),   # nominal (the note you name the bell by)
    (2.514, 0.32, 0.26),   # superquint
    (2.662, 0.22, 0.22),
    (3.011, 0.30, 0.20),   # octave nominal
    (4.166, 0.18, 0.13),
    (5.433, 0.12, 0.09),
    (6.796, 0.08, 0.06),
    (8.215, 0.05, 0.045),
]


def bell(note: float, seconds: float, t60: float = 9.0, amp: float = 0.5, strike: float = 0.5,
         rng: np.random.Generator | None = None, warmth: float = 0.0, detune_cents: float = 4.0,
         partials=None) -> np.ndarray:
    """A struck bell. `note` is the MIDI pitch of the nominal (the named note); `strike` adds the
    metallic attack noise; `warmth` (0..1) tilts the upper partials down for a mellower bell."""
    rng = rng or np.random.default_rng(7)
    n = samples(seconds)
    if n <= 0:
        return np.zeros(0)
    f0 = float(midi_to_hz(note)) * 0.5  # the nominal is 2x the fundamental
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, a, dm in (partials or BELL_PARTIALS):
        f = f0 * ratio * (1.0 + rng.normal(0.0, detune_cents * 1e-4))
        if f >= SR * 0.47 or f < 8.0:
            continue
        tilt = 1.0 - warmth * min(ratio / 8.0, 1.0)
        decay = np.exp(-np.log(1000.0) * t / max(t60 * dm, 0.02))
        # a slow beat between two slightly detuned copies: real bells shimmer
        beat_hz = rng.uniform(0.15, 0.8) * ratio ** 0.4
        shimmer = 1.0 + 0.10 * np.sin(TWO_PI * beat_hz * t + rng.uniform(0, TWO_PI))
        out += a * tilt * decay * shimmer * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
    out /= np.sum([p[1] for p in (partials or BELL_PARTIALS)])
    # Each partial starts at a random phase, so without an attack the sum steps away from zero
    # on the first sample and every strike clicks. A bell does rise almost instantly, but not
    # in one sample: a 2 ms raised-cosine rise is inaudible and leaves the waveform continuous.
    na = min(samples(0.002), n)
    if na > 1:
        out[:na] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, na))
    # strike transient: a short filtered noise burst with the bell's own resonances
    if strike > 0.0:
        ns = min(samples(0.05), n)
        burst = osc.white(ns, rng) * envmod.perc(ns, 0.0005, 0.03)
        burst = filters.bandpass(burst, f0 * 4.0, 1.2) + 0.5 * filters.highpass(burst, f0 * 6.0)
        out[:ns] += burst * strike * 0.5
    # a touch of body: the air the bell moves
    out += 0.05 * strike * filters.lowpass(osc.white(n, rng) * envmod.perc(n, 0.001, 0.12), f0 * 2.0)
    return out * amp


def toll_bell(note: float, seconds: float = 16.0, amp: float = 0.5,
              rng: np.random.Generator | None = None) -> np.ndarray:
    """The Cracked Toll: a forty-metre bell, so very low, very long, and cracked -- a slight
    buzz on the prime and a second partial series a whisker sharp, beating against the first."""
    rng = rng or np.random.default_rng(11)
    base = bell(note, seconds, t60=26.0, amp=1.0, strike=0.35, rng=rng, warmth=0.35)
    crack = bell(note + 0.14, seconds, t60=18.0, amp=0.42, strike=0.0,
                 rng=np.random.default_rng(rng.integers(1 << 30)), warmth=0.5)
    y = base + crack
    n = len(y)
    # the crack rattles: a little amplitude-modulated distortion that dies with the strike
    rattle_env = envmod.expdecay(n, 1.6)
    y = y + fx.saturate(y * rattle_env, 3.0, "tanh") * 0.10 * rattle_env
    return filters.dc_block(y) * amp


def hand_bell(note: float, seconds: float = 2.2, amp: float = 0.4,
              rng: np.random.Generator | None = None) -> np.ndarray:
    """A small bright hand bell: higher partials, short decay, a hard clapper."""
    rng = rng or np.random.default_rng(5)
    parts = [(r, a * (1.0 + 0.5 * (r > 2.0)), d * 0.5) for r, a, d in BELL_PARTIALS]
    y = bell(note, seconds, t60=2.4, amp=1.0, strike=0.85, rng=rng, warmth=-0.1, partials=parts)
    return filters.highpass(y, 300.0) * amp


def bell_fm(note: float, seconds: float, index: float = 6.0, ratio: float = 1.41, t60: float = 4.0,
            amp: float = 0.4) -> np.ndarray:
    """A cheaper FM bell (inharmonic carrier:modulator ratio) for layering and for small chimes."""
    n = samples(seconds)
    t = np.arange(n) / SR
    f = float(midi_to_hz(note))
    mod_env = np.exp(-np.log(1000.0) * t / max(t60 * 0.3, 0.02))
    car_env = np.exp(-np.log(1000.0) * t / max(t60, 0.02))
    modv = np.sin(TWO_PI * f * ratio * t) * index * mod_env
    return np.sin(TWO_PI * f * t + modv) * car_env * amp


def chime_run(notes, seconds: float, spacing: float = 0.28, amp: float = 0.35,
              rng: np.random.Generator | None = None, t60: float = 3.0) -> np.ndarray:
    """A run of small chimes (used for jingles and the Mending school)."""
    rng = rng or np.random.default_rng(3)
    n = samples(seconds)
    out = np.zeros(n)
    for i, nt in enumerate(notes):
        s = samples(i * spacing)
        if s >= n:
            break
        y = hand_bell(nt, min(seconds - i * spacing, t60), amp=1.0, rng=rng)
        out[s:s + len(y)] += y[:n - s] * (0.85 ** i)
    return out * amp


# =================================================================================================
# Strings
# =================================================================================================

def pluck(note: float, seconds: float, amp: float = 0.4, damping: float = 0.5, brightness: float = 0.5,
          rng: np.random.Generator | None = None, pick_pos: float = 0.28, stretch: float = 0.0,
          decay: float | None = None) -> np.ndarray:
    """Karplus-Strong plucked string with a tunable fractional-delay loop, a one-pole loop filter
    (damping), comb filtering for the picking position and optional all-pass stretch (for a
    slightly inharmonic, lute-like tone).

    `decay` is the -60 dB ring time in seconds; when omitted it comes from `damping`
    (0 = a ringing open string, 1 = a heavily damped, muted one). The loop gain has to be set
    per round trip, not per sample: a string at 220 Hz makes 220 trips a second."""
    rng = rng or np.random.default_rng(2)
    n = samples(seconds)
    if n <= 0:
        return np.zeros(0)
    f = float(midi_to_hz(note))
    delay = SR / f
    D = int(delay)
    frac = delay - D
    if D < 2:
        return np.zeros(n)
    # excitation: filtered noise burst, brighter for a harder pick
    exc_len = min(D, n)
    exc = osc.white(exc_len, rng)
    exc = filters.lowpass(exc, 800.0 + 9000.0 * brightness, 0.7)
    exc *= np.hanning(len(exc)) ** 0.4
    buf = np.zeros(n + D + 2)
    buf[:exc_len] = exc
    # loop gain for the requested ring time: a^(trips per t60) = 1/1000
    t60 = float(decay) if decay is not None else float(np.clip(4.5 * (1.0 - 0.8 * damping), 0.25, 9.0))
    a = float(np.clip(10.0 ** (-3.0 * D / max(t60 * SR, 1.0)), 0.80, 0.99995))
    lp = float(np.clip(0.2 + 0.6 * (1.0 - brightness), 0.05, 0.9))
    # The loop is evaluated a whole delay-line length at a time: everything a block needs from
    # the delay line was written by the previous block, so only the one-pole loop filter's state
    # has to be carried across blocks.
    zi = np.zeros(1)
    total = n + D
    for s in range(D + 1, total, D):
        e = min(s + D, total)
        seg = buf[s - D:e - D] * (1.0 - frac) + buf[s - D - 1:e - D - 1] * frac
        filt, zi = signal.lfilter([1.0 - lp], [1.0, -lp], seg, zi=zi)
        buf[s:e] += a * filt
    y = buf[:n]
    # picking position comb
    pp = max(int(delay * float(np.clip(pick_pos, 0.02, 0.5))), 1)
    if pp < n:
        y = y - 0.7 * np.concatenate([np.zeros(pp), y[:-pp]])
    if stretch > 0.0:
        y = filters.allpass(y, f * 3.0, 0.5 + stretch)
    y = filters.dc_block(y)
    y *= envmod.segments([(0.0, 1.0), (max(seconds - 0.08, 0.01), 1.0), (seconds, 0.0)], n)
    return y * amp * 0.9


def harp(notes, seconds: float, spacing: float = 0.09, amp: float = 0.3,
         rng: np.random.Generator | None = None) -> np.ndarray:
    """A rolled chord on gut strings (Hearthvale, Brightwater)."""
    rng = rng or np.random.default_rng(4)
    n = samples(seconds)
    out = np.zeros(n)
    for i, nt in enumerate(notes):
        s = samples(i * spacing)
        if s >= n:
            break
        y = pluck(nt, (n - s) / SR, amp=1.0, damping=0.35, brightness=0.55, rng=rng, pick_pos=0.22)
        out[s:s + len(y)] += y
    return out * amp


def bowed(note: float, seconds: float, amp: float = 0.3, bow_pressure: float = 0.5,
          brightness: float = 0.5, vibrato: float = 0.4, rng: np.random.Generator | None = None,
          attack: float = 0.12, release: float = 0.35) -> np.ndarray:
    """Bowed string: a sawtooth-ish excitation shaped by the bow (a noisy, slightly chaotic
    stick-slip drive) run through a string resonator bank with body formants."""
    rng = rng or np.random.default_rng(6)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    f = float(midi_to_hz(note))
    t = np.arange(n) / SR
    # pitch: slow vibrato that arrives after the attack, plus a little human drift
    vib_env = np.clip((t - attack * 1.4) / 0.4, 0.0, 1.0)
    vib = np.sin(TWO_PI * (5.2 + rng.uniform(-0.5, 0.5)) * t) * vibrato * 0.008 * vib_env
    drift = envmod.wander(n, rng, 0.7, 0.004)
    freq = f * (1.0 + vib + drift)
    drive = osc.saw(freq, n)
    # bow noise: the scrape rides on the string, strongest at the attack
    scrape = osc.white(n, rng) * (0.12 + 0.3 * bow_pressure)
    scrape *= np.exp(-t / 0.25) * 0.8 + 0.2
    drive = drive * (0.82 + 0.18 * envmod.wander(n, rng, 6.0, 1.0)) + scrape * 0.35
    # string + body: a few resonances of the instrument's box
    body = filters.modal(drive * 0.5, [(f * 0.99, 0.35, 0.5), (280.0, 0.12, 0.35), (460.0, 0.10, 0.28),
                                       (720.0, 0.08, 0.2), (1300.0, 0.05, 0.12)], norm="bp")
    y = drive * 0.55 + body * 0.9
    cutoff = f * (3.5 + 6.0 * brightness) + 400.0
    y = filters.svf(y, np.clip(cutoff * (0.6 + 0.6 * np.clip(t / attack, 0, 1)), 200, 16000), 0.9, "lp")
    y = filters.highpass(y, max(f * 0.6, 40.0), 0.7)
    e = envmod.adsr(seconds, a=attack, d=0.25, s=0.82, r=release, curve=1.6, total=n / SR)
    return filters.dc_block(y * e) * amp * 0.6


def cello_section(notes, seconds: float, amp: float = 0.25, rng: np.random.Generator | None = None,
                  spread_cents: float = 7.0, **kw) -> np.ndarray:
    """Two or three bowed players per note, slightly apart in time and tuning."""
    rng = rng or np.random.default_rng(8)
    n = samples(seconds + kw.get("release", 0.35))
    out = np.zeros(n)
    for nt in np.atleast_1d(notes):
        for k in range(2):
            det = rng.normal(0.0, spread_cents) / 100.0
            delay = samples(abs(rng.normal(0.0, 0.012)))
            y = bowed(float(nt) + det, seconds, amp=1.0, rng=rng, **kw)
            if delay < n:
                out[delay:delay + len(y)] += y[:n - delay] * 0.6
    return out * amp


# =================================================================================================
# Winds
# =================================================================================================

def flute(note: float, seconds: float, amp: float = 0.3, breath: float = 0.35, vibrato: float = 0.35,
          rng: np.random.Generator | None = None, attack: float = 0.06, release: float = 0.25,
          octave_mix: float = 0.25) -> np.ndarray:
    """Flute / whistle: a blown-edge tone = breath noise through a resonant pipe plus a soft
    sine body, with the chiff at the start that makes it read as a flute."""
    rng = rng or np.random.default_rng(9)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    f = float(midi_to_hz(note))
    t = np.arange(n) / SR
    vib_env = np.clip((t - attack * 2.0) / 0.5, 0.0, 1.0)
    vib = np.sin(TWO_PI * (4.8 + rng.uniform(-0.4, 0.4)) * t + rng.uniform(0, 6.0)) * vibrato * 0.006 * vib_env
    freq = f * (1.0 + vib + envmod.wander(n, rng, 0.9, 0.003))
    tone = osc.sine(freq, n) + octave_mix * osc.sine(freq * 2.0, n) + 0.08 * osc.sine(freq * 3.0, n)
    # breath: noise band-passed at the pipe's resonance, modulated by the tone (turbulence)
    br = osc.white(n, rng)
    br = filters.bandpass(br, f * 2.0, 1.4) * 0.6 + filters.bandpass(br, f * 4.0, 2.0) * 0.3
    br *= (0.6 + 0.4 * np.abs(tone))
    chiff = osc.white(n, rng) * envmod.perc(n, 0.004, 0.05)
    chiff = filters.bandpass(chiff, f * 3.0, 0.8)
    y = tone * (1.0 - breath * 0.35) + br * breath + chiff * 0.35 * breath
    y = filters.lowpass(y, f * 8.0 + 2000.0, 0.7)
    e = envmod.adsr(seconds, a=attack, d=0.15, s=0.88, r=release, curve=1.5, total=n / SR)
    return filters.dc_block(y * e) * amp * 0.8


def whistle(note: float, seconds: float, amp: float = 0.25, **kw) -> np.ndarray:
    """A thinner, higher flute (tin whistle, the Vale's pub instrument)."""
    kw.setdefault("breath", 0.45)
    kw.setdefault("octave_mix", 0.4)
    return flute(note, seconds, amp, **kw)


def pipes(note: float, seconds: float, amp: float = 0.3, reed: float = 0.6, drone: bool = False,
          rng: np.random.Generator | None = None, attack: float = 0.04, release: float = 0.2) -> np.ndarray:
    """Skerrow pipes: a buzzing reed (narrow pulse) through the pipe's formants. With drone=True
    the envelope is flat and the tone is steadier (for the drone pipe underneath)."""
    rng = rng or np.random.default_rng(13)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    f = float(midi_to_hz(note))
    t = np.arange(n) / SR
    wob = envmod.wander(n, rng, 0.5 if drone else 2.0, 0.004 if drone else 0.008)
    freq = f * (1.0 + wob)
    pw = 0.18 + 0.12 * reed + 0.03 * np.sin(TWO_PI * 0.7 * t)
    y = osc.square(freq, n, pw=float(np.mean(pw)))
    y = y * 0.7 + osc.saw(freq, n) * 0.3
    # the chanter's formants: two fixed resonances give the nasal pipe colour
    y = filters.formant_bank(y, [(f * 2.0, 180, 0.9), (1100, 250, 0.5), (2300, 400, 0.25)]) + y * 0.35
    y = fx.saturate(y, 1.4 + reed, "tanh", 0.6)
    y = filters.lowpass(y, 5200.0, 0.8)
    if drone:
        e = envmod.adsr(seconds, a=max(attack, 0.25), d=0.2, s=0.95, r=max(release, 0.6), curve=1.3,
                        total=n / SR)
    else:
        e = envmod.adsr(seconds, a=attack, d=0.1, s=0.9, r=release, curve=1.6, total=n / SR)
    return filters.dc_block(y * e) * amp * 0.45


def drone(note: float, seconds: float, amp: float = 0.25, rng: np.random.Generator | None = None,
          voices: int = 3, fifth: bool = True, bite: float = 0.3) -> np.ndarray:
    """A sustained pipe/hurdy drone: detuned pulses plus the fifth, formant-shaped, very slow
    movement. Used under Skerrow and for the Cinderlea sustained note's lower body."""
    rng = rng or np.random.default_rng(17)
    n = samples(seconds)
    out = np.zeros(n)
    partials = [0.0, 7.0] if fifth else [0.0]
    for p in partials:
        for v in range(voices):
            det = rng.normal(0.0, 6.0) / 1200.0
            f = float(midi_to_hz(note + p)) * (1.0 + det)
            wob = envmod.wander(n, rng, 0.12, 0.002)
            y = osc.square(f * (1.0 + wob), n, pw=0.3 + 0.1 * rng.random())
            out += y * (0.7 if p == 0 else 0.4) / voices
    out = filters.formant_bank(out, [(220, 120, 0.8), (700, 200, 0.5), (1600, 400, 0.2)]) + out * 0.4
    out = fx.saturate(out, 1.0 + bite, "tanh", 0.5)
    out = filters.lowpass(out, 3200.0, 0.7)
    return filters.dc_block(out) * amp * 0.5


# =================================================================================================
# Voices and pads
# =================================================================================================

def choir(notes, seconds: float, amp: float = 0.22, vowel: str = "ah", rng: np.random.Generator | None = None,
          voices: int = 3, attack: float = 0.5, release: float = 1.2, breath: float = 0.2,
          detune_cents: float = 9.0) -> np.ndarray:
    """Choir-ish pad: detuned saws per note through vowel formants, each voice with its own slow
    pitch drift and vibrato, plus a breath layer. Returns mono; spread it with fx.decorrelate."""
    rng = rng or np.random.default_rng(21)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    out = np.zeros(n)
    t = np.arange(n) / SR
    for nt in np.atleast_1d(notes):
        for v in range(voices):
            det = rng.normal(0.0, detune_cents) / 1200.0
            f = float(midi_to_hz(float(nt))) * (1.0 + det)
            vib = np.sin(TWO_PI * (4.3 + rng.uniform(-0.8, 0.8)) * t + rng.uniform(0, 6.0)) * 0.004
            vib *= np.clip((t - attack) / 0.8, 0.0, 1.0)
            drift = envmod.wander(n, rng, 0.25, 0.003)
            sig = osc.saw(f * (1.0 + vib + drift), n)
            out += sig / (voices * max(len(np.atleast_1d(notes)), 1))
    out = filters.vowel(out, vowel) * 1.6 + out * 0.12
    if breath > 0.0:
        br = filters.bandpass(osc.white(n, rng), 2200.0, 0.7) + filters.bandpass(osc.white(n, rng), 900.0, 1.0)
        out += br * breath * 0.25
    out = filters.lowpass(out, 7000.0, 0.7)
    e = envmod.adsr(seconds, a=attack, d=0.6, s=0.85, r=release, curve=1.4, total=n / SR)
    return filters.dc_block(out * e) * amp


def hum(note: float, seconds: float, amp: float = 0.25, rng: np.random.Generator | None = None,
        attack: float = 1.2, release: float = 2.0, closed: float = 0.8) -> np.ndarray:
    """A human hum: the sustained note under Cinderlea. A glottal pulse train through a nearly
    closed mouth (mm), with the small irregularities of a person holding a note too long."""
    rng = rng or np.random.default_rng(23)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    f = float(midi_to_hz(note))
    t = np.arange(n) / SR
    jitter = envmod.wander(n, rng, 1.1, 0.0035) + envmod.wander(n, rng, 0.17, 0.004)
    vib = np.sin(TWO_PI * 4.6 * t + rng.uniform(0, 6)) * 0.0025 * np.clip((t - attack) / 1.5, 0, 1)
    freq = f * (1.0 + jitter + vib)
    # glottal source: a soft pulse train (rounded saw) with shimmer
    src = osc.saw(freq, n) * 0.6 + osc.square(freq, n, 0.42) * 0.25
    src = filters.lowpass(src, f * 12.0, 0.7)
    shimmer = 1.0 + 0.06 * envmod.wander(n, rng, 3.0, 1.0)
    src *= shimmer
    voiced = filters.vowel(src, "mm") * closed + filters.vowel(src, "oo") * (1.0 - closed)
    voiced = voiced * 1.8 + src * 0.08
    breath = filters.bandpass(osc.white(n, rng), 1400.0, 0.6) * 0.05
    y = voiced + breath
    y = filters.lowpass(y, 3600.0, 0.7)
    e = envmod.adsr(seconds, a=attack, d=1.0, s=0.9, r=release, curve=1.3, total=n / SR)
    return filters.dc_block(y * e) * amp


def pad(notes, seconds: float, amp: float = 0.2, rng: np.random.Generator | None = None,
        brightness: float = 0.45, attack: float = 1.5, release: float = 2.5, voices: int = 3,
        detune_cents: float = 11.0, shimmer: float = 0.25) -> np.ndarray:
    """The harmony bed: slow detuned saw/triangle stack through a moving low-pass, with an
    octave-up shimmer layer. Mono; the generators spread it themselves."""
    rng = rng or np.random.default_rng(29)
    n = samples(seconds + release)
    if n <= 0:
        return np.zeros(0)
    out = np.zeros(n)
    notes = list(np.atleast_1d(notes))
    for nt in notes:
        for v in range(voices):
            det = rng.normal(0.0, detune_cents) / 1200.0
            f = float(midi_to_hz(float(nt))) * (1.0 + det)
            drift = envmod.wander(n, rng, 0.13, 0.0035)
            mix = 0.55 + 0.25 * rng.random()
            sig = osc.saw(f * (1.0 + drift), n) * mix + osc.triangle(f * (1.0 + drift), n) * (1.0 - mix)
            out += sig / (voices * max(len(notes), 1))
    if shimmer > 0.0:
        sh = np.zeros(n)
        for nt in notes[:2]:
            f = float(midi_to_hz(float(nt) + 12.0)) * (1.0 + rng.normal(0, 6) / 1200.0)
            sh += osc.triangle(f * (1.0 + envmod.wander(n, rng, 0.2, 0.004)), n)
        out += sh * shimmer * 0.25 / max(len(notes[:2]), 1)
    t = np.arange(n) / SR
    cut = (500.0 + 5500.0 * brightness) * (0.45 + 0.55 * np.clip(t / max(attack, 0.01), 0, 1))
    cut = cut * (1.0 + 0.25 * envmod.wander(n, rng, 0.08, 1.0))
    out = filters.svf(out, np.clip(cut, 180.0, 15000.0), 0.8, "lp", block=256)
    out = filters.highpass(out, 60.0, 0.7)
    e = envmod.adsr(seconds, a=attack, d=1.2, s=0.86, r=release, curve=1.3, total=n / SR)
    return filters.dc_block(out * e) * amp


def glass_pad(notes, seconds: float, amp: float = 0.18, rng: np.random.Generator | None = None,
              attack: float = 2.0, release: float = 3.0) -> np.ndarray:
    """A colder, glassier pad (Skerrow, Cinderlea): sine stacks with inharmonic upper partials."""
    rng = rng or np.random.default_rng(31)
    n = samples(seconds + release)
    out = np.zeros(n)
    notes = list(np.atleast_1d(notes))
    for nt in notes:
        f = float(midi_to_hz(float(nt)))
        for k, (mult, a) in enumerate([(1.0, 1.0), (2.0, 0.4), (3.02, 0.18), (4.17, 0.09), (5.41, 0.05)]):
            ff = f * mult * (1.0 + rng.normal(0, 4) / 1200.0)
            if ff > SR * 0.45:
                continue
            drift = envmod.wander(n, rng, 0.09 + 0.05 * k, 0.002)
            out += osc.sine(ff * (1.0 + drift), n) * a / max(len(notes), 1)
    e = envmod.adsr(seconds, a=attack, d=1.5, s=0.88, r=release, curve=1.2, total=n / SR)
    return out * e * amp * 0.5


# =================================================================================================
# Percussion
# =================================================================================================

def membrane(freq: float = 90.0, seconds: float = 0.8, amp: float = 0.5, tension: float = 1.0,
             rng: np.random.Generator | None = None, strike_hardness: float = 0.5,
             pitch_drop: float = 0.25) -> np.ndarray:
    """A drum head: circular-membrane modal ratios (Bessel zeros) excited by a short strike, with
    the pitch drop of a real head as it relaxes."""
    rng = rng or np.random.default_rng(37)
    n = samples(seconds)
    if n <= 0:
        return np.zeros(0)
    ratios = [1.0, 1.593, 2.135, 2.295, 2.917, 3.598, 3.652]
    gains = [1.0, 0.55, 0.36, 0.3, 0.2, 0.13, 0.1]
    t60s = [seconds * 0.85, seconds * 0.5, seconds * 0.35, seconds * 0.3, seconds * 0.2,
            seconds * 0.15, seconds * 0.13]
    exc_n = max(samples(0.0015 + 0.004 * (1.0 - strike_hardness)), 2)
    exc = np.zeros(n)
    exc[:exc_n] = osc.white(exc_n, rng) * np.hanning(exc_n)
    exc[:exc_n] += np.hanning(exc_n) * 0.6
    t = np.arange(n) / SR
    bend = 1.0 + pitch_drop * np.exp(-t / 0.06)
    out = np.zeros(n)
    for r, g, t60 in zip(ratios, gains, t60s):
        f = freq * r * tension
        if f >= SR * 0.47:
            continue
        # time-varying pitch: render as a decaying sine with the bend applied to phase
        ph = TWO_PI * np.cumsum(f * bend) / SR
        out += g * np.sin(ph) * np.exp(-np.log(1000.0) * t / max(t60, 0.02))
    out = out / sum(gains)
    out += filters.lowpass(exc, 2500.0) * 0.4 * strike_hardness
    return filters.dc_block(out) * amp


def frame_drum(seconds: float = 0.9, amp: float = 0.5, freq: float = 78.0,
               rng: np.random.Generator | None = None) -> np.ndarray:
    """A wide, soft, low frame drum (the heartbeat under combat)."""
    rng = rng or np.random.default_rng(41)
    y = membrane(freq, seconds, amp=1.0, rng=rng, strike_hardness=0.35, pitch_drop=0.35)
    y = filters.lowpass(y, 900.0, 0.7)
    y += filters.lowpass(osc.brown(len(y), rng), 180.0) * envmod.perc(len(y), 0.002, 0.18) * 0.5
    return filters.dc_block(y) * amp


def war_drum(seconds: float = 1.4, amp: float = 0.6, freq: float = 58.0,
             rng: np.random.Generator | None = None) -> np.ndarray:
    """Bigger, with a rope-tensioned rattle: boss music."""
    rng = rng or np.random.default_rng(43)
    y = membrane(freq, seconds, amp=1.0, rng=rng, strike_hardness=0.6, pitch_drop=0.4)
    rattle = osc.crackle(len(y), rng, 700.0, 2.0) * envmod.perc(len(y), 0.001, 0.13)
    y += filters.bandpass(rattle, 2600.0, 0.8) * 0.16
    y = fx.saturate(y, 1.6, "tanh", 0.35)
    return filters.dc_block(y) * amp


def wood_block(seconds: float = 0.25, amp: float = 0.4, freq: float = 900.0,
               rng: np.random.Generator | None = None, hardness: float = 0.7) -> np.ndarray:
    """A struck wooden bar/block: a few sharp inharmonic modes, very short."""
    rng = rng or np.random.default_rng(47)
    n = samples(seconds)
    exc = np.zeros(n)
    k = max(samples(0.0008), 2)
    exc[:k] = osc.white(k, rng) * np.hanning(k)
    modes = [(freq, 0.09 * seconds / 0.25, 1.0), (freq * 2.71, 0.05 * seconds / 0.25, 0.5),
             (freq * 5.15, 0.03 * seconds / 0.25, 0.22), (freq * 8.9, 0.02 * seconds / 0.25, 0.08)]
    y = filters.modal(exc, modes)
    y += filters.highpass(exc, 3000.0) * 0.4 * hardness
    y = filters.dc_block(y)
    p = np.max(np.abs(y)) + 1e-9
    return y / p * amp


def shaker(seconds: float = 0.22, amp: float = 0.3, rng: np.random.Generator | None = None,
           grains: int = 60, bright: float = 0.6) -> np.ndarray:
    """A shaker/rattle: many tiny high-frequency grains under one envelope."""
    rng = rng or np.random.default_rng(53)
    n = samples(seconds)
    y = osc.crackle(n, rng, grains / max(seconds, 0.01), 1.0, 1.6)
    y = filters.bandpass(y, 5000.0 + 4000.0 * bright, 0.7) + filters.highpass(y, 8000.0) * 0.5
    y *= envmod.segments([(0.0, 0.0), (0.012, 1.0), (seconds * 0.45, 0.5), (seconds, 0.0)], n)
    return y * amp * 1.5


def tambour_roll(seconds: float, amp: float = 0.25, rate_hz: float = 14.0, freq: float = 120.0,
                 rng: np.random.Generator | None = None, crescendo: bool = True) -> np.ndarray:
    """A drum roll (boss phase changes, the Toll's approach)."""
    rng = rng or np.random.default_rng(59)
    n = samples(seconds)
    out = np.zeros(n)
    t = 0.0
    while t < seconds:
        s = samples(t)
        hit = membrane(freq * rng.uniform(0.95, 1.06), 0.22, amp=1.0, rng=rng, strike_hardness=0.5)
        k = min(len(hit), n - s)
        if k > 0:
            out[s:s + k] += hit[:k] * rng.uniform(0.5, 1.0)
        t += (1.0 / rate_hz) * rng.uniform(0.82, 1.18)
    if crescendo:
        out *= np.linspace(0.25, 1.0, n) ** 1.5
    return filters.dc_block(out) * amp


def cymbal_swell(seconds: float = 2.0, amp: float = 0.25, rng: np.random.Generator | None = None,
                 reverse: bool = False) -> np.ndarray:
    """A shimmering metal swell from dense inharmonic partials (not a sample of a cymbal: a bank
    of 70 random high resonators excited by noise)."""
    rng = rng or np.random.default_rng(61)
    n = samples(seconds)
    exc = osc.white(n, rng) * 0.5
    modes = []
    for _ in range(70):
        f = rng.uniform(1200.0, 14000.0)
        modes.append((f, rng.uniform(0.25, 1.4), rng.uniform(0.2, 1.0) * (1200.0 / f) ** 0.3))
    y = filters.modal(exc * envmod.perc(n, 0.005, seconds * 0.4), modes)
    y = filters.highpass(y, 900.0, 0.7)
    shape = np.linspace(0.0, 1.0, n) ** 2 if reverse else envmod.perc(n, 0.01, seconds * 0.5)
    y = filters.dc_block(y * shape)
    p = np.max(np.abs(y)) + 1e-9
    return y / p * amp
