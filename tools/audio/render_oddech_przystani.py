#!/usr/bin/env python3
"""Render the original looping Base theme "Oddech Przystani".

The renderer intentionally uses only NumPy and Python's standard library.  All
time-based effects are circular: note tails and room reflections leaving the
end of the 60-bar form are wrapped back to its beginning.  This makes the
result a real musical cycle instead of a track with a fade-out hidden behind a
runtime restart.

Composition brief:
  * 64 BPM, 4/4, 60 bars (exactly 225 seconds at 48 kHz), D minor/Dorian;
  * intimate organic-mechanical ambient, without vocals or a drum backbeat;
  * a sparse four-note identity appears late and only three times;
  * felt-key, bowed-pad, low pulse, water-glass and muted-metal colours;
  * deterministic bow/felt grain and irregular micro-dynamics for organic motion;
  * no dominant cadence or final accent at the loop boundary.

The output is a temporary 16-bit PCM WAV intended for a constant-gain master
pass and Ogg Vorbis encoding.  The runtime asset is generated separately so
the encoded file can be measured again after lossy compression.
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 48_000
BPM = 64.0
BEAT_SECONDS = 60.0 / BPM
BAR_SECONDS = BEAT_SECONDS * 4.0
BAR_COUNT = 60
DURATION_SECONDS = BAR_SECONDS * BAR_COUNT
FRAME_COUNT = int(round(DURATION_SECONDS * SAMPLE_RATE))
RNG_SEED = 2_608_092_026


CHORDS: dict[str, tuple[int, ...]] = {
    "dm9_a": (45, 50, 53, 57, 60, 64),
    "bbmaj7_f": (41, 46, 50, 53, 57),
    "fadd9_a": (45, 48, 53, 55, 57),
    "c6_g": (43, 48, 52, 57, 62),
    "dm69_a": (45, 50, 53, 59, 64),
    "gm9_d": (38, 43, 46, 50, 53, 57),
    "am7_e": (40, 45, 48, 55),
    "dm_f": (41, 45, 50, 52, 57),
    "csus2_g": (43, 48, 50, 55, 62),
    "asus4_e": (40, 45, 50, 52, 57),
    "gm6_d": (38, 43, 46, 52, 57),
}


# One harmony every two bars.  The last two blocks return to the opening field
# without a dominant cadence, so looping is a continuation rather than a reset.
HARMONIC_FORM: tuple[str, ...] = (
    "dm9_a", "bbmaj7_f", "fadd9_a", "c6_g", "dm69_a", "dm9_a",
    "gm9_d", "bbmaj7_f", "c6_g", "dm69_a", "am7_e", "bbmaj7_f",
    "fadd9_a", "c6_g", "dm9_a", "dm69_a", "bbmaj7_f", "gm9_d",
    "dm_f", "csus2_g", "fadd9_a", "bbmaj7_f", "gm9_d", "asus4_e",
    "dm9_a", "c6_g", "bbmaj7_f", "gm6_d", "dm9_a", "dm9_a",
)


def midi_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def raised_envelope(
    frame_count: int,
    attack_seconds: float,
    release_seconds: float,
) -> np.ndarray:
    env = np.ones(frame_count, dtype=np.float32)
    attack = min(frame_count, max(1, int(round(attack_seconds * SAMPLE_RATE))))
    release = min(frame_count, max(1, int(round(release_seconds * SAMPLE_RATE))))
    if attack + release > frame_count:
        scale = frame_count / float(attack + release)
        attack = max(1, int(attack * scale))
        release = max(1, frame_count - attack)
    env[:attack] = np.sin(np.linspace(0.0, math.pi * 0.5, attack, dtype=np.float32)) ** 2
    env[-release:] = np.cos(np.linspace(0.0, math.pi * 0.5, release, dtype=np.float32)) ** 2
    return env


def equal_power_pan(pan: float) -> tuple[float, float]:
    position = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi * 0.25
    return math.cos(position), math.sin(position)


def irregular_gain(
    frame_count: int,
    seed_value: float,
    depth: float,
    spacing_seconds: float,
) -> np.ndarray:
    """Return a slowly changing deterministic gain curve with no obvious LFO."""
    spacing = max(2, int(round(spacing_seconds * SAMPLE_RATE)))
    control_frames = np.arange(0, frame_count + spacing, spacing, dtype=np.int64)
    if control_frames[-1] < frame_count - 1:
        control_frames = np.append(control_frames, frame_count - 1)
    seed = (int(round((seed_value + 31.0) * 1_000_003.0)) ^ 0x5F3759DF) & 0xFFFFFFFF
    rng = np.random.default_rng(seed)
    controls = rng.normal(0.0, 0.54, control_frames.size).astype(np.float32)
    controls = np.clip(controls, -1.0, 1.0)
    frames = np.arange(frame_count, dtype=np.int64)
    curve = np.interp(frames, control_frames, controls).astype(np.float32)
    return 1.0 + curve * depth


def add_circular(
    target: np.ndarray,
    mono: np.ndarray,
    start_seconds: float,
    gain: float,
    pan: float,
) -> None:
    if mono.size == 0 or gain == 0.0:
        return
    start = int(round(start_seconds * SAMPLE_RATE)) % FRAME_COUNT
    left_gain, right_gain = equal_power_pan(pan)
    remaining = mono.size
    source_offset = 0
    destination = start
    while remaining > 0:
        take = min(remaining, FRAME_COUNT - destination)
        section = mono[source_offset:source_offset + take]
        target[destination:destination + take, 0] += section * (gain * left_gain)
        target[destination:destination + take, 1] += section * (gain * right_gain)
        remaining -= take
        source_offset += take
        destination = 0


def pad_voice(freq: float, duration_seconds: float, phase_seed: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    vibrato = (
        0.0080 * np.sin(2.0 * math.pi * 0.071 * t + phase_seed)
        + 0.0035 * np.sin(2.0 * math.pi * 0.113 * t + phase_seed * 0.71)
    )
    phase = 2.0 * math.pi * freq * t + vibrato
    signal = (
        np.sin(phase)
        + 0.23 * np.sin(2.0 * phase + 0.37 + phase_seed * 0.13)
        + 0.11 * np.sin(3.0 * phase + 1.17)
        + 0.045 * np.sin(5.0 * phase + 0.59)
    )
    slow_bow = 0.86 + 0.14 * np.sin(2.0 * math.pi * 0.19 * t + phase_seed)
    slow_bow *= irregular_gain(frames, phase_seed, 0.052, 0.41)
    env = raised_envelope(frames, 3.1, 3.8)
    return (signal * slow_bow * env * 0.67).astype(np.float32)


def bass_bow(freq: float, duration_seconds: float, phase_seed: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    vibrato = 0.010 * np.sin(2.0 * math.pi * 0.083 * t + phase_seed)
    phase = 2.0 * math.pi * freq * t + vibrato
    signal = (
        np.sin(phase)
        + 0.31 * np.sin(2.0 * phase + 0.22)
        + 0.14 * np.sin(3.0 * phase + 0.91)
        + 0.06 * np.sin(4.0 * phase + 1.41)
    )
    env = raised_envelope(frames, 4.0, 5.0)
    motion = irregular_gain(frames, phase_seed + 7.3, 0.035, 0.58)
    return (signal * env * motion * 0.69).astype(np.float32)


def felt_key(freq: float, duration_seconds: float, colour: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    attack = np.minimum(1.0, t / 0.024)
    body = np.exp(-t * (0.78 + colour * 0.12))
    phase = 2.0 * math.pi * freq * t
    signal = (
        np.sin(phase)
        + 0.31 * np.sin(2.003 * phase + 0.21)
        + 0.13 * np.sin(3.992 * phase + 0.82)
        + 0.045 * np.sin(6.03 * phase + 1.67)
    )
    felt = 0.10 * np.sin(2.0 * math.pi * max(48.0, freq * 0.49) * t) * np.exp(-t * 17.0)
    release = raised_envelope(frames, 0.01, min(0.9, duration_seconds * 0.34))
    touch = irregular_gain(frames, colour + 13.7, 0.045, 0.17)
    return ((signal * touch * attack * body + felt) * release * 0.56).astype(np.float32)


def bowed_solo(freq: float, duration_seconds: float, phase_seed: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    vibrato = 0.020 * np.sin(2.0 * math.pi * 4.65 * t + phase_seed)
    slow_drift = 0.006 * np.sin(2.0 * math.pi * 0.09 * t + phase_seed * 0.3)
    phase = 2.0 * math.pi * freq * t + vibrato + slow_drift
    signal = (
        np.sin(phase)
        + 0.20 * np.sin(2.0 * phase + 0.4)
        + 0.09 * np.sin(3.0 * phase + 1.2)
    )
    env = raised_envelope(frames, min(2.8, duration_seconds * 0.3), min(3.2, duration_seconds * 0.35))
    bow_pressure = irregular_gain(frames, phase_seed + 19.1, 0.075, 0.23)
    return (signal * env * bow_pressure * 0.64).astype(np.float32)


def water_glass(freq: float, duration_seconds: float, colour: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    ratios = (1.0, 2.01, 2.92, 4.18, 5.43)
    weights = (1.0, 0.28, 0.17, 0.095, 0.055)
    decays = (0.74, 1.05, 1.36, 1.70, 2.05)
    signal = np.zeros(frames, dtype=np.float32)
    for ratio, weight, decay in zip(ratios, weights, decays):
        signal += (
            weight
            * np.sin(2.0 * math.pi * freq * ratio * t + colour * ratio)
            * np.exp(-t * decay)
        ).astype(np.float32)
    attack = np.minimum(1.0, t / 0.055)
    release = raised_envelope(frames, 0.01, min(1.2, duration_seconds * 0.30))
    return (signal * attack * release * 0.47).astype(np.float32)


def muted_platform_pulse(freq: float, duration_seconds: float, colour: float) -> np.ndarray:
    frames = max(1, int(round(duration_seconds * SAMPLE_RATE)))
    t = np.arange(frames, dtype=np.float32) / SAMPLE_RATE
    fundamental = np.sin(2.0 * math.pi * freq * t + colour) * np.exp(-t * 2.5)
    hull = 0.22 * np.sin(2.0 * math.pi * freq * 2.73 * t + 0.8) * np.exp(-t * 4.6)
    wake = 0.11 * np.sin(2.0 * math.pi * freq * 0.51 * t + 1.3) * np.exp(-t * 1.8)
    attack = np.minimum(1.0, t / 0.085)
    return ((fundamental + hull + wake) * attack * 0.51).astype(np.float32)


def add_periodic_air(target: np.ndarray, rng: np.random.Generator) -> None:
    """Add a quiet Fourier texture whose oscillators are exact loop harmonics."""
    partial_count = 22
    frequencies = np.geomspace(155.0, 3_100.0, partial_count)
    cycle_numbers = np.maximum(1, np.rint(frequencies * DURATION_SECONDS).astype(np.int64))
    phases_l = rng.uniform(0.0, 2.0 * math.pi, partial_count)
    phases_r = phases_l + rng.uniform(-0.75, 0.75, partial_count)
    weights = (1.0 / np.sqrt(frequencies / frequencies[0])).astype(np.float32)
    weights /= float(np.sum(weights))

    chunk = 240_000
    for start in range(0, FRAME_COUNT, chunk):
        end = min(FRAME_COUNT, start + chunk)
        indices = np.arange(start, end, dtype=np.float64)
        left = np.zeros(end - start, dtype=np.float32)
        right = np.zeros(end - start, dtype=np.float32)
        for cycle, weight, phase_l, phase_r in zip(cycle_numbers, weights, phases_l, phases_r):
            base = (2.0 * math.pi * float(cycle) / FRAME_COUNT) * indices
            left += (weight * np.sin(base + phase_l)).astype(np.float32)
            right += (weight * np.sin(base + phase_r)).astype(np.float32)
        # Two very slow exact-cycle envelopes make the air breathe without a
        # beginning or an end and keep it behind the pitched material.
        theta = 2.0 * math.pi * indices / FRAME_COUNT
        breath_l = 0.70 + 0.18 * np.sin(3.0 * theta + 0.2) + 0.12 * np.sin(7.0 * theta + 1.1)
        breath_r = 0.70 + 0.18 * np.sin(3.0 * theta + 0.8) + 0.12 * np.sin(7.0 * theta + 1.7)
        target[start:end, 0] += left * breath_l.astype(np.float32) * 0.016
        target[start:end, 1] += right * breath_r.astype(np.float32) * 0.016


def add_organic_surface(target: np.ndarray, rng: np.random.Generator) -> None:
    """Add quiet periodic bow/felt grain with a broad, non-tonal spectrum.

    The random spectrum is rendered as one exact 225-second Fourier cycle, so
    it has the irregularity of filtered noise while remaining safe at the loop
    boundary.  Independent channels put width only into this upper texture;
    bass and the mechanical pulse remain centred.
    """
    bin_count = FRAME_COUNT // 2 + 1
    frequencies = np.fft.rfftfreq(FRAME_COUNT, d=1.0 / SAMPLE_RATE)
    high_pass = 1.0 - np.exp(-np.power(frequencies / 520.0, 4.0))
    low_pass = np.exp(-np.power(frequencies / 2_650.0, 4.0))
    presence = 0.72 + 0.28 * np.exp(-0.5 * np.square((frequencies - 1_150.0) / 620.0))
    response = (high_pass * low_pass * presence).astype(np.float32)
    response[0] = 0.0

    chunk = 240_000
    for channel, phase in ((0, 0.23), (1, 1.41)):
        real = rng.standard_normal(bin_count, dtype=np.float32)
        imaginary = rng.standard_normal(bin_count, dtype=np.float32)
        spectrum = (real + 1j * imaginary).astype(np.complex64, copy=False)
        spectrum *= response
        spectrum[0] = 0.0
        spectrum[-1] = complex(float(spectrum[-1].real), 0.0)
        texture = np.fft.irfft(spectrum, n=FRAME_COUNT).astype(np.float32)
        texture_rms = math.sqrt(float(np.mean(np.square(texture, dtype=np.float64))))
        if texture_rms > 1.0e-12:
            texture /= texture_rms
        del spectrum, real, imaginary

        for start in range(0, FRAME_COUNT, chunk):
            end = min(FRAME_COUNT, start + chunk)
            indices = np.arange(start, end, dtype=np.float64)
            theta = 2.0 * math.pi * indices / FRAME_COUNT
            grain_motion = (
                0.70
                + 0.16 * np.sin(5.0 * theta + phase)
                + 0.09 * np.sin(13.0 * theta + phase * 1.7)
                + 0.05 * np.sin(29.0 * theta + phase * 0.6)
            )
            target[start:end, channel] += (
                texture[start:end] * grain_motion.astype(np.float32) * 0.00135
            )
        del texture


def render_composition() -> np.ndarray:
    rng = np.random.default_rng(RNG_SEED)
    mix = np.zeros((FRAME_COUNT, 2), dtype=np.float32)
    room_send = np.zeros_like(mix)

    add_periodic_air(mix, rng)
    add_organic_surface(mix, rng)

    block_seconds = BAR_SECONDS * 2.0
    pad_duration = block_seconds + 7.2
    for index, chord_name in enumerate(HARMONIC_FORM):
        chord = CHORDS[chord_name]
        start = index * block_seconds - 3.25
        section_shape = 0.92 + 0.08 * math.sin(2.0 * math.pi * index / len(HARMONIC_FORM) - 0.7)
        for voice_index, note in enumerate(chord):
            frequency = midi_hz(note)
            seed = 0.41 * index + 0.73 * voice_index
            voice = pad_voice(frequency, pad_duration, seed)
            register_gain = 0.66 if note < 45 else (0.84 if note < 57 else 0.74)
            pan = -0.42 + 0.84 * (voice_index / max(1, len(chord) - 1))
            pan += 0.07 * math.sin(index * 0.91 + voice_index)
            gain = 0.0215 * section_shape * register_gain
            add_circular(mix, voice, start, gain, pan)
            add_circular(room_send, voice, start, gain * 0.78, -pan * 0.55)

    # A four-bar low foundation changes half as often as the pads.  It keeps
    # the centre stable while upper voices provide the modal colour.
    bass_notes = (38, 41, 45, 43, 38, 41, 43, 38, 41, 45, 43, 40, 38, 41, 38)
    bass_duration = BAR_SECONDS * 4.0 + 8.0
    for index, note in enumerate(bass_notes):
        start = index * BAR_SECONDS * 4.0 - 3.8
        voice = bass_bow(midi_hz(note), bass_duration, 0.33 + index * 0.57)
        gain = 0.0195 * (0.94 + 0.06 * math.sin(index * 1.13))
        add_circular(mix, voice, start, gain, -0.04 if index % 2 == 0 else 0.04)
        add_circular(room_send, voice, start, gain * 0.42, 0.0)

    # Sparse felt-key figures.  The four-note identity [D, F, E, A] is delayed
    # until bar 9 and returns only as two changed recollections.
    key_events: list[tuple[float, float, int, float, float]] = [
        (2, 0.0, 57, 4.8, 0.74), (4, 2.0, 53, 4.2, 0.67), (6, 0.5, 60, 4.5, 0.62),
        (9, 0.0, 62, 5.1, 0.82), (9, 1.5, 65, 5.0, 0.77),
        (10, 0.25, 64, 5.0, 0.72), (10, 2.25, 69, 6.2, 0.76),
        (13, 1.0, 57, 4.0, 0.57), (15, 0.0, 60, 4.6, 0.61),
        (17, 2.0, 62, 4.8, 0.64), (19, 0.5, 65, 4.4, 0.59),
        (21, 2.5, 64, 4.6, 0.56), (23, 0.0, 60, 5.4, 0.58),
        (27, 0.0, 62, 5.3, 0.78), (27, 1.75, 64, 4.8, 0.70),
        (28, 0.75, 65, 5.0, 0.75), (29, 2.5, 69, 6.4, 0.73),
        (32, 0.0, 72, 5.8, 0.46), (34, 2.0, 69, 5.6, 0.49),
        (37, 1.0, 57, 4.6, 0.61), (39, 0.0, 62, 5.2, 0.70),
        (41, 2.0, 65, 5.1, 0.67), (43, 0.5, 64, 4.8, 0.63),
        (45, 2.0, 59, 5.4, 0.58),
        (47, 0.0, 62, 5.2, 0.71), (47, 2.0, 65, 5.0, 0.65),
        (48, 1.0, 64, 5.0, 0.59), (49, 3.0, 57, 6.0, 0.61),
        (52, 0.5, 60, 4.7, 0.48), (54, 2.0, 57, 5.1, 0.45),
    ]
    for event_index, (bar, beat, note, duration, velocity) in enumerate(key_events):
        voice = felt_key(midi_hz(note), duration, event_index * 0.17)
        start = bar * BAR_SECONDS + beat * BEAT_SECONDS
        pan = 0.34 * math.sin(event_index * 1.79)
        gain = 0.050 * velocity
        add_circular(mix, voice, start, gain, pan)
        add_circular(room_send, voice, start, gain * 0.88, -pan * 0.72)

    # A human, viola/cello-like line enters only in the later middle.  It is
    # deliberately fragmentary and never points to a final tonic at bar 60.
    solo_events: tuple[tuple[float, float, int, float, float], ...] = (
        (35, 0.0, 50, 10.5, 0.60), (38, 0.5, 53, 9.8, 0.66),
        (41, 0.0, 52, 10.2, 0.61), (44, 0.5, 57, 9.4, 0.58),
        (47, 1.0, 55, 8.8, 0.52), (50, 0.0, 53, 9.0, 0.47),
    )
    for event_index, (bar, beat, note, duration, velocity) in enumerate(solo_events):
        voice = bowed_solo(midi_hz(note), duration, 1.2 + event_index * 0.83)
        start = bar * BAR_SECONDS + beat * BEAT_SECONDS
        pan = -0.17 + event_index * 0.065
        gain = 0.035 * velocity
        add_circular(mix, voice, start, gain, pan)
        add_circular(room_send, voice, start, gain * 0.90, -pan)

    # Muted pulses suggest breathing machinery and a hull moving on water.  No
    # backbeat is established; rests lengthen in the quiet opening and ending.
    pulse_bars = (12, 14, 16, 19, 21, 23, 26, 29, 31, 34, 37, 40, 42, 45, 48, 52)
    for event_index, bar in enumerate(pulse_bars):
        note = 38 if event_index % 4 in (0, 3) else 43
        voice = muted_platform_pulse(midi_hz(note), 2.2, event_index * 0.37)
        start = bar * BAR_SECONDS + (0.0 if event_index % 3 else 1.5 * BEAT_SECONDS)
        pan = -0.19 if event_index % 2 == 0 else 0.19
        gain = 0.0225 * (0.90 + 0.10 * math.sin(event_index))
        add_circular(mix, voice, start, gain, pan)
        add_circular(room_send, voice, start, gain * 0.58, -pan)

    # Water/metal reflections are infrequent, soft and non-literal.  The late
    # event wraps its decay into the opening and helps the room feel continuous.
    glass_events = (
        (3, 2.5, 74), (7, 0.5, 69), (11, 3.0, 76), (16, 1.0, 72),
        (20, 2.5, 79), (25, 0.0, 74), (30, 3.0, 81), (34, 1.5, 76),
        (39, 2.0, 72), (43, 3.0, 79), (49, 1.0, 74), (54, 2.5, 69),
        (58, 1.5, 76),
    )
    for event_index, (bar, beat, note) in enumerate(glass_events):
        voice = water_glass(midi_hz(note), 7.5, event_index * 0.43 + 0.2)
        start = bar * BAR_SECONDS + beat * BEAT_SECONDS
        pan = -0.72 + 1.44 * ((event_index * 7) % len(glass_events)) / max(1, len(glass_events) - 1)
        gain = 0.017 * (0.90 + 0.10 * math.sin(event_index * 0.8))
        add_circular(mix, voice, start, gain, pan)
        add_circular(room_send, voice, start, gain * 1.05, -pan * 0.88)

    # Circular room: finite, low-gain reflections use rolled copies of the
    # complete send.  Tails crossing EOF therefore already exist at sample 0.
    reflection_taps = (
        (0.173, 0.115, False), (0.269, 0.096, True),
        (0.431, 0.079, False), (0.683, 0.064, True),
        (1.071, 0.052, False), (1.697, 0.041, True),
        (2.633, 0.031, False), (4.109, 0.022, True),
    )
    for delay_seconds, gain, crossfeed in reflection_taps:
        shift = int(round(delay_seconds * SAMPLE_RATE))
        if crossfeed:
            mix[:, 0] += np.roll(room_send[:, 1], shift) * gain
            mix[:, 1] += np.roll(room_send[:, 0], shift) * gain
        else:
            mix[:, 0] += np.roll(room_send[:, 0], shift) * gain
            mix[:, 1] += np.roll(room_send[:, 1], shift) * gain

    # Bass sources are already nearly central; preserve more of the independent
    # upper reflections and organic grain so the room is open without making
    # the low foundation unstable.  A sample-wise soft curve catches rare
    # stacked resonances without introducing state at the seam.
    mid = (mix[:, 0] + mix[:, 1]) * 0.5
    side = (mix[:, 0] - mix[:, 1]) * 0.5 * 0.98
    mix[:, 0] = mid + side
    mix[:, 1] = mid - side
    mix -= np.mean(mix, axis=0, keepdims=True, dtype=np.float64).astype(np.float32)
    mix = (np.tanh(mix * 1.16) / math.tanh(1.16)).astype(np.float32)

    # A reproducible preliminary level.  Final LUFS matching is constant-gain
    # only and is performed after measuring this PCM render.
    rms = math.sqrt(float(np.mean(np.square(mix, dtype=np.float64))))
    target_rms = 10.0 ** (-25.5 / 20.0)
    if rms > 1.0e-9:
        mix *= target_rms / rms
    peak = float(np.max(np.abs(mix)))
    if peak > 0.48:
        mix *= 0.48 / peak
    return mix


def write_pcm16(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        chunk = 240_000
        for start in range(0, audio.shape[0], chunk):
            section = np.clip(audio[start:start + chunk], -1.0, 1.0)
            pcm = np.rint(section * 32767.0).astype("<i2", copy=False)
            wav.writeframesraw(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Temporary stereo PCM WAV output")
    args = parser.parse_args()

    audio = render_composition()
    write_pcm16(args.output, audio)
    peak = float(np.max(np.abs(audio)))
    rms = math.sqrt(float(np.mean(np.square(audio, dtype=np.float64))))
    print(f"Rendered: {args.output}")
    print(f"Format: PCM16 stereo, {SAMPLE_RATE} Hz")
    print(f"Form: {BAR_COUNT} bars, {BPM:.1f} BPM, {DURATION_SECONDS:.3f} s, {FRAME_COUNT} frames")
    print(f"Sample peak: {20.0 * math.log10(max(peak, 1.0e-12)):.2f} dBFS")
    print(f"Unweighted RMS: {20.0 * math.log10(max(rms, 1.0e-12)):.2f} dBFS")


if __name__ == "__main__":
    main()
