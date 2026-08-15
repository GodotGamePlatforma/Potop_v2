#!/usr/bin/env python3
"""Generate the non-verbal narrative SFX palette used by NarrativeAudioCatalog.

The assets are deterministic 48 kHz stereo PCM one-shots.  They deliberately
avoid speech, formants and UI-style confirmation tones: the palette is built
from relays, oxidized metal, radio noise, pumps and low storm pressure.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 48_000
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "assets" / "audio" / "narrative"


class StereoBuffer:
    def __init__(self, duration: float, seed: int) -> None:
        self.duration = duration
        self.frames = max(1, int(round(duration * SAMPLE_RATE)))
        self.left = [0.0] * self.frames
        self.right = [0.0] * self.frames
        self.random = random.Random(seed)

    def _pan(self, pan: float) -> tuple[float, float]:
        angle = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi * 0.25
        return math.cos(angle), math.sin(angle)

    @staticmethod
    def _envelope(position: float, duration: float, attack: float, release: float) -> float:
        if position < 0.0 or position >= duration:
            return 0.0
        attack_gain = 1.0 if attack <= 0.0 else min(position / attack, 1.0)
        remaining = duration - position
        release_gain = 1.0 if release <= 0.0 else min(remaining / release, 1.0)
        return attack_gain * release_gain

    def add_damped_tone(
        self,
        start: float,
        duration: float,
        frequency: float,
        amplitude: float,
        decay: float,
        pan: float = 0.0,
        end_frequency: float | None = None,
        modulation_hz: float = 0.0,
        modulation_depth: float = 0.0,
    ) -> None:
        first = max(0, int(start * SAMPLE_RATE))
        last = min(self.frames, int((start + duration) * SAMPLE_RATE))
        left_gain, right_gain = self._pan(pan)
        phase = 0.0
        for index in range(first, last):
            local = (index - first) / SAMPLE_RATE
            progress = local / max(duration, 1.0 / SAMPLE_RATE)
            current_frequency = frequency
            if end_frequency is not None:
                current_frequency = frequency + (end_frequency - frequency) * progress
            phase += math.tau * current_frequency / SAMPLE_RATE
            envelope = math.exp(-local / max(decay, 0.001))
            if modulation_hz > 0.0:
                envelope *= 1.0 - modulation_depth + modulation_depth * (0.5 + 0.5 * math.sin(math.tau * modulation_hz * local))
            sample = math.sin(phase) * amplitude * envelope
            self.left[index] += sample * left_gain
            self.right[index] += sample * right_gain

    def add_tone_bed(
        self,
        start: float,
        duration: float,
        frequency: float,
        amplitude: float,
        attack: float,
        release: float,
        pan: float = 0.0,
        modulation_hz: float = 0.0,
        modulation_depth: float = 0.0,
        end_frequency: float | None = None,
    ) -> None:
        first = max(0, int(start * SAMPLE_RATE))
        last = min(self.frames, int((start + duration) * SAMPLE_RATE))
        left_gain, right_gain = self._pan(pan)
        phase = 0.0
        for index in range(first, last):
            local = (index - first) / SAMPLE_RATE
            progress = local / max(duration, 1.0 / SAMPLE_RATE)
            current_frequency = frequency if end_frequency is None else frequency + (end_frequency - frequency) * progress
            phase += math.tau * current_frequency / SAMPLE_RATE
            envelope = self._envelope(local, duration, attack, release)
            if modulation_hz > 0.0:
                envelope *= 1.0 - modulation_depth + modulation_depth * (0.5 + 0.5 * math.sin(math.tau * modulation_hz * local))
            sample = math.sin(phase) * amplitude * envelope
            self.left[index] += sample * left_gain
            self.right[index] += sample * right_gain

    def _filtered_noise(self, count: int, low_hz: float, high_hz: float) -> list[float]:
        raw = [self.random.uniform(-1.0, 1.0) for _ in range(count)]

        def lowpass(values: list[float], cutoff: float) -> list[float]:
            if cutoff <= 0.0:
                return [0.0] * len(values)
            coefficient = 1.0 - math.exp(-math.tau * min(cutoff, SAMPLE_RATE * 0.45) / SAMPLE_RATE)
            output: list[float] = []
            state = 0.0
            for value in values:
                state += coefficient * (value - state)
                output.append(state)
            return output

        upper = lowpass(raw, high_hz)
        if low_hz <= 0.0:
            return upper
        lower = lowpass(raw, low_hz)
        return [high - low for high, low in zip(upper, lower)]

    def add_noise(
        self,
        start: float,
        duration: float,
        amplitude: float,
        low_hz: float,
        high_hz: float,
        attack: float,
        release: float,
        pan: float = 0.0,
        dropout_hz: float = 0.0,
        dropout_depth: float = 0.0,
    ) -> None:
        first = max(0, int(start * SAMPLE_RATE))
        last = min(self.frames, int((start + duration) * SAMPLE_RATE))
        count = max(0, last - first)
        if count == 0:
            return
        values = self._filtered_noise(count, low_hz, high_hz)
        left_gain, right_gain = self._pan(pan)
        for offset, value in enumerate(values):
            local = offset / SAMPLE_RATE
            envelope = self._envelope(local, duration, attack, release)
            if dropout_hz > 0.0:
                dropout = 0.5 + 0.5 * math.sin(math.tau * dropout_hz * local + 1.3)
                envelope *= 1.0 - dropout_depth * dropout * dropout
            sample = value * amplitude * envelope
            self.left[first + offset] += sample * left_gain
            self.right[first + offset] += sample * right_gain

    def add_metal_impact(self, time: float, strength: float = 1.0, pan: float = 0.0, dark: bool = False) -> None:
        self.add_noise(time, 0.045, 1.5 * strength, 500.0 if dark else 900.0, 5_000.0 if dark else 9_000.0, 0.001, 0.035, pan)
        partials = (72.0, 121.0, 213.0, 337.0) if dark else (105.0, 187.0, 313.0, 521.0)
        for partial_index, frequency in enumerate(partials):
            self.add_damped_tone(
                time,
                0.55,
                frequency,
                strength * (0.42 / (partial_index + 1)),
                0.10 + partial_index * 0.055,
                pan,
            )

    def add_relay_click(self, time: float, strength: float = 1.0, pan: float = 0.0) -> None:
        self.add_noise(time, 0.018, 1.25 * strength, 1_400.0, 10_000.0, 0.0005, 0.014, pan)
        self.add_damped_tone(time, 0.16, 145.0, 0.34 * strength, 0.035, pan)
        self.add_damped_tone(time + 0.006, 0.12, 460.0, 0.16 * strength, 0.027, pan)

    def add_pump_cycle(self, time: float, strength: float, pan: float = 0.0, broken: bool = False) -> None:
        self.add_damped_tone(time, 0.42, 68.0, 0.75 * strength, 0.15, pan, 43.0)
        self.add_damped_tone(time + 0.025, 0.26, 116.0, 0.28 * strength, 0.08, pan, 72.0)
        exhale_duration = 0.48 if broken else 0.66
        self.add_noise(time + 0.14, exhale_duration, 0.46 * strength, 180.0, 1_650.0, 0.025, 0.28, pan)
        if not broken:
            self.add_relay_click(time + 0.78, 0.24 * strength, pan)
        else:
            self.add_noise(time + 0.48, 0.12, 0.22 * strength, 250.0, 1_100.0, 0.005, 0.1, pan)

    def finalize(self, target_peak: float = 0.68) -> tuple[list[int], float]:
        edge = min(int(0.008 * SAMPLE_RATE), self.frames // 4)
        for index in range(edge):
            fade = index / max(edge, 1)
            self.left[index] *= fade
            self.right[index] *= fade
            self.left[-1 - index] *= fade
            self.right[-1 - index] *= fade
        peak = max(max(abs(value) for value in self.left), max(abs(value) for value in self.right), 1e-9)
        gain = min(target_peak / peak, 4.0)
        interleaved: list[int] = []
        measured_peak = 0.0
        for left, right in zip(self.left, self.right):
            for value in (left * gain, right * gain):
                limited = math.tanh(value * 1.08) / math.tanh(1.08)
                limited = max(-0.999, min(0.999, limited))
                measured_peak = max(measured_peak, abs(limited))
                interleaved.append(int(round(limited * 32_767.0)))
        return interleaved, measured_peak


def line_engage() -> StereoBuffer:
    sound = StereoBuffer(1.25, 101)
    sound.add_metal_impact(0.08, 0.92, dark=True)
    sound.add_relay_click(0.27, 0.62)
    sound.add_tone_bed(0.34, 0.84, 56.0, 0.22, 0.08, 0.18, modulation_hz=12.0, modulation_depth=0.10)
    sound.add_noise(0.34, 0.82, 0.17, 40.0, 260.0, 0.07, 0.18)
    return sound


def radio_open() -> StereoBuffer:
    sound = StereoBuffer(0.82, 102)
    sound.add_relay_click(0.04, 0.72, -0.08)
    sound.add_noise(0.17, 0.60, 0.58, 850.0, 6_200.0, 0.12, 0.08, dropout_hz=13.0, dropout_depth=0.12)
    sound.add_noise(0.20, 0.54, 0.20, 120.0, 720.0, 0.08, 0.10)
    return sound


def radio_fade() -> StereoBuffer:
    sound = StereoBuffer(0.45, 103)
    sound.add_noise(0.0, 0.43, 0.62, 650.0, 5_600.0, 0.005, 0.35, dropout_hz=9.0, dropout_depth=0.18)
    sound.add_relay_click(0.30, 0.30, 0.08)
    return sound


def radio_distant() -> StereoBuffer:
    sound = StereoBuffer(1.02, 104)
    sound.add_relay_click(0.07, 0.34, 0.45)
    sound.add_noise(0.17, 0.80, 0.55, 420.0, 7_800.0, 0.10, 0.13, 0.32, dropout_hz=6.5, dropout_depth=0.55)
    sound.add_noise(0.25, 0.68, 0.24, 70.0, 560.0, 0.08, 0.15, 0.22, dropout_hz=3.2, dropout_depth=0.35)
    return sound


def pumps_stable() -> StereoBuffer:
    sound = StereoBuffer(2.80, 105)
    sound.add_pump_cycle(0.14, 0.86, -0.12)
    sound.add_pump_cycle(1.42, 0.86, 0.12)
    sound.add_noise(0.08, 2.58, 0.12, 35.0, 180.0, 0.12, 0.22)
    return sound


def pumps_emergency() -> StereoBuffer:
    sound = StereoBuffer(2.72, 106)
    sound.add_pump_cycle(0.17, 0.82, -0.18)
    sound.add_pump_cycle(1.51, 0.61, 0.20, broken=True)
    sound.add_noise(0.12, 2.43, 0.13, 40.0, 220.0, 0.08, 0.28, dropout_hz=2.4, dropout_depth=0.25)
    return sound


def archive_relay() -> StereoBuffer:
    sound = StereoBuffer(2.02, 107)
    for start, pan in ((0.10, -0.28), (0.68, 0.24)):
        sound.add_noise(start, 0.34, 0.54, 180.0, 2_800.0, 0.025, 0.10, pan, dropout_hz=24.0, dropout_depth=0.32)
        sound.add_relay_click(start + 0.35, 0.46, pan)
    sound.add_metal_impact(1.38, 0.62, dark=True)
    sound.add_relay_click(1.62, 0.54)
    return sound


def r3_startup() -> StereoBuffer:
    sound = StereoBuffer(3.45, 108)
    for start, strength, pan in ((0.18, 0.74, -0.18), (0.83, 0.86, 0.16)):
        sound.add_metal_impact(start, strength, pan, dark=True)
        sound.add_damped_tone(start + 0.04, 0.58, 52.0, 0.46 * strength, 0.22, pan, 34.0)
    sound.add_tone_bed(1.34, 1.98, 35.0, 0.25, 0.38, 0.24, modulation_hz=10.5, modulation_depth=0.18, end_frequency=49.0)
    sound.add_noise(1.30, 2.02, 0.20, 45.0, 420.0, 0.35, 0.22, dropout_hz=10.5, dropout_depth=0.13)
    return sound


def c4_single_line() -> StereoBuffer:
    sound = StereoBuffer(2.08, 109)
    sound.add_metal_impact(0.15, 0.72, -0.72, dark=True)
    sound.add_tone_bed(0.24, 0.72, 62.0, 0.16, 0.03, 0.26, -0.72, modulation_hz=14.0, modulation_depth=0.16)
    sound.add_metal_impact(0.82, 0.76, 0.72, dark=True)
    sound.add_relay_click(1.22, 0.66, -0.60)
    sound.add_noise(1.22, 0.30, 0.32, 120.0, 1_200.0, 0.006, 0.22, -0.50)
    sound.add_metal_impact(1.56, 0.56, 0.0, dark=True)
    return sound


def splitter_bench_latch() -> StereoBuffer:
    sound = StereoBuffer(1.08, 110)
    for time, pan, strength in ((0.11, -0.22, 0.25), (0.18, 0.16, 0.18), (0.25, -0.04, 0.13)):
        sound.add_relay_click(time, strength, pan)
    sound.add_metal_impact(0.46, 0.54, -0.42, dark=True)
    sound.add_metal_impact(0.78, 0.54, 0.42, dark=True)
    return sound


def c4_dual_test() -> StereoBuffer:
    sound = StereoBuffer(2.20, 111)
    sound.add_metal_impact(0.18, 0.66, -0.72, dark=True)
    sound.add_tone_bed(0.27, 1.35, 58.0, 0.13, 0.04, 0.24, -0.62, modulation_hz=11.0, modulation_depth=0.10)
    sound.add_metal_impact(0.78, 0.66, 0.72, dark=True)
    sound.add_tone_bed(0.87, 0.78, 61.0, 0.13, 0.04, 0.24, 0.62, modulation_hz=11.0, modulation_depth=0.10)
    sound.add_relay_click(1.58, 0.66, 0.0)
    return sound


def c4_dual_storm() -> StereoBuffer:
    sound = StereoBuffer(2.62, 112)
    for index, time in enumerate((0.14, 0.64, 1.14, 1.64)):
        pan = -0.66 if index % 2 == 0 else 0.66
        sound.add_metal_impact(time, 0.50, pan, dark=True)
        sound.add_tone_bed(time + 0.06, 0.54, 56.0 + index * 1.8, 0.11, 0.02, 0.18, pan, modulation_hz=12.0, modulation_depth=0.10)
    sound.add_relay_click(2.10, 0.60)
    sound.add_noise(0.12, 2.30, 0.10, 45.0, 250.0, 0.12, 0.22)
    return sound


def front_pressure() -> StereoBuffer:
    sound = StereoBuffer(5.25, 113)
    sound.add_noise(0.0, 5.12, 0.47, 20.0, 280.0, 1.65, 0.72, dropout_hz=0.31, dropout_depth=0.18)
    sound.add_noise(1.15, 3.75, 0.20, 260.0, 1_900.0, 1.10, 0.72, -0.20, dropout_hz=0.52, dropout_depth=0.26)
    sound.add_tone_bed(1.05, 3.62, 84.0, 0.18, 1.25, 0.82, -0.18, modulation_hz=0.74, modulation_depth=0.42, end_frequency=58.0)
    sound.add_tone_bed(2.08, 2.60, 137.0, 0.10, 0.75, 0.72, 0.28, modulation_hz=1.10, modulation_depth=0.34, end_frequency=111.0)
    sound.add_metal_impact(3.92, 0.33, 0.10, dark=True)
    return sound


SOUNDS = {
    "line_engage.wav": (line_engage, 0.67),
    "radio_channel_open.wav": (radio_open, 0.58),
    "radio_channel_fade.wav": (radio_fade, 0.52),
    "radio_distant_channel.wav": (radio_distant, 0.48),
    "pumps_stable.wav": (pumps_stable, 0.66),
    "pumps_emergency.wav": (pumps_emergency, 0.64),
    "archive_relay_read.wav": (archive_relay, 0.61),
    "r3_startup.wav": (r3_startup, 0.66),
    "c4_single_line.wav": (c4_single_line, 0.64),
    "splitter_bench_latch.wav": (splitter_bench_latch, 0.58),
    "c4_dual_line_test.wav": (c4_dual_test, 0.62),
    "c4_dual_line_storm.wav": (c4_dual_storm, 0.64),
    "front_pressure.wav": (front_pressure, 0.60),
}


def write_wave(path: Path, sound: StereoBuffer, target_peak: float) -> float:
    samples, measured_peak = sound.finalize(target_peak)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(struct.pack("<%dh" % len(samples), *samples))
    return measured_peak


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, (factory, target_peak) in SOUNDS.items():
        sound = factory()
        measured_peak = write_wave(OUTPUT_DIR / filename, sound, target_peak)
        peak_db = 20.0 * math.log10(max(measured_peak, 1e-9))
        print(f"{filename:30s} {sound.duration:4.2f} s  peak {peak_db:5.2f} dBFS")


if __name__ == "__main__":
    main()
