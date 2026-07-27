"""Generate deterministic PL FFT input, complex-output, and power vectors."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import zlib

import numpy as np


ROOT = Path(__file__).resolve().parents[4]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from PROJECT.verification.fft.model.xilinx_fft_cmodel import simulate_fft


FFT_SIZE = 2048
SCALE_SCHEDULE = 0x6AB
VECTOR_DIR = Path(__file__).resolve().parents[1] / "vectors"


def _tone(bin_index: int, amplitude: int) -> tuple[np.ndarray, np.ndarray]:
    sample = np.arange(FFT_SIZE)
    phase = 2.0 * np.pi * bin_index * sample / FFT_SIZE
    return (
        np.rint(amplitude * np.cos(phase)).astype(np.int16),
        np.rint(amplitude * np.sin(phase)).astype(np.int16),
    )


def _cases() -> list[tuple[str, np.ndarray, np.ndarray]]:
    zeros = np.zeros(FFT_SIZE, dtype=np.int16)
    impulse = zeros.copy()
    impulse[0] = 32767
    tone_137 = _tone(137, 4096)
    tone_1901 = _tone(1901, 4096)
    tie_a = _tone(300, 2048)
    tie_b = _tone(700, 2048)
    tie_i = np.add(tie_a[0], tie_b[0], dtype=np.int16)
    tie_q = np.add(tie_a[1], tie_b[1], dtype=np.int16)
    near_full_scale = _tone(137, 32767)
    return [
        ("zeros", zeros, zeros),
        ("impulse", impulse, zeros),
        ("tone_bin_137", *tone_137),
        ("tone_bin_1901", *tone_1901),
        ("two_tone_tie", tie_i, tie_q),
        ("near_full_scale", *near_full_scale),
    ]


def _pack_complex(real: np.ndarray, imag: np.ndarray) -> np.ndarray:
    real_bits = real.view(np.uint16).astype(np.uint32)
    imag_bits = imag.view(np.uint16).astype(np.uint32)
    return (imag_bits << 16) | real_bits


def _hex_payload(words: np.ndarray, width: int) -> bytes:
    return ("".join(f"{int(word):0{width}X}\n" for word in words)).encode("ascii")


def _peak(power: np.ndarray, search_start: int, search_stop: int, dc_guard: int) -> int:
    eligible = np.ones(FFT_SIZE, dtype=bool)
    eligible[: dc_guard + 1] = False
    if dc_guard:
        eligible[FFT_SIZE - dc_guard :] = False
    eligible[:search_start] = False
    eligible[search_stop + 1 :] = False
    candidates = np.flatnonzero(eligible)
    if candidates.size == 0:
        raise ValueError("search and DC guard settings leave no eligible FFT bin")
    return int(candidates[np.argmax(power[candidates])])


def build_payloads() -> dict[str, bytes]:
    payloads: dict[str, bytes] = {}
    manifest_cases = []
    search_start = 0
    search_stop = FFT_SIZE - 1
    dc_guard = 0

    for name, i_samples, q_samples in _cases():
        case_dc_guard = 4 if name == "impulse" else dc_guard
        result = simulate_fft(i_samples, q_samples, SCALE_SCHEDULE)
        input_words = _pack_complex(i_samples, q_samples)
        fft_words = _pack_complex(result.real, result.imag)
        power = result.real.astype(np.int64) ** 2 + result.imag.astype(np.int64) ** 2
        power_words = power.astype(np.uint64)
        peak_bin = _peak(power_words, search_start, search_stop, case_dc_guard)

        input_file = f"{name}.input.hex"
        fft_file = f"{name}.fft.hex"
        power_file = f"{name}.power.hex"
        payloads[input_file] = _hex_payload(input_words, 8)
        payloads[fft_file] = _hex_payload(fft_words, 8)
        payloads[power_file] = _hex_payload(power_words, 16)
        crc = zlib.crc32(input_words.astype("<u4", copy=False).tobytes()) & 0xFFFFFFFF

        manifest_cases.append(
            {
                "dc_guard": case_dc_guard,
                "fft_file": fft_file,
                "input_crc32": f"0x{crc:08X}",
                "input_file": input_file,
                "name": name,
                "nfft": FFT_SIZE,
                "overflow": result.overflow,
                "peak_bin": peak_bin,
                "peak_im": int(result.imag[peak_bin]),
                "peak_power": int(power_words[peak_bin]),
                "peak_re": int(result.real[peak_bin]),
                "power_file": power_file,
                "search_start": search_start,
                "search_stop": search_stop,
            }
        )

    manifest = {
        "cases": manifest_cases,
        "crc": {
            "algorithm": "CRC-32/ISO-HDLC",
            "serialized_word": "{Q[15:0],I[15:0]}",
            "word_byte_order": "little-endian",
        },
        "fft": {
            "component_format": "signed Q1.15",
            "nfft": FFT_SIZE,
            "output_order": "natural",
            "scale_schedule": f"0x{SCALE_SCHEDULE:03X}",
            "total_shift": 12,
        },
        "format_version": 1,
        "power_format": "unsigned 33-bit in bits [32:0] of a 64-bit word",
    }
    payloads["manifest.json"] = (
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    return payloads


def write_or_check(check: bool) -> None:
    payloads = build_payloads()
    if check:
        mismatches = [
            name
            for name, expected in payloads.items()
            if not (VECTOR_DIR / name).is_file()
            or (VECTOR_DIR / name).read_bytes() != expected
        ]
        if mismatches:
            raise SystemExit(
                "FFT vector files are missing or stale: " + ", ".join(mismatches)
            )
    else:
        VECTOR_DIR.mkdir(parents=True, exist_ok=True)
        for name, payload in payloads.items():
            (VECTOR_DIR / name).write_bytes(payload)
    print("PASS: 6 FFT vector sets are reproducible")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare generated bytes with checked-in vectors without modifying them",
    )
    args = parser.parse_args()
    write_or_check(args.check)


if __name__ == "__main__":
    main()
