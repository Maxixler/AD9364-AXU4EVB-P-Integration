"""Reproducibility and format tests for checked-in PL FFT vectors."""

import json
from pathlib import Path
import unittest
import zlib

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
VECTOR_DIR = ROOT / "PROJECT" / "verification" / "fft" / "vectors"
MANIFEST_PATH = VECTOR_DIR / "manifest.json"
EXPECTED_CASES = {
    "zeros",
    "impulse",
    "tone_bin_137",
    "tone_bin_1901",
    "two_tone_tie",
    "near_full_scale",
}


def _read_hex_words(path: Path, dtype: np.dtype) -> np.ndarray:
    lines = path.read_text(encoding="ascii").splitlines()
    return np.asarray([int(line, 16) for line in lines], dtype=dtype)


class FftVectorContractTests(unittest.TestCase):
    def test_manifest_declares_all_required_cases_and_formats(self) -> None:
        self.assertTrue(MANIFEST_PATH.is_file(), "FFT vector manifest has not been generated")

        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cases = {case["name"]: case for case in manifest["cases"]}

        self.assertEqual(manifest["format_version"], 1)
        self.assertEqual(manifest["fft"]["nfft"], 2048)
        self.assertEqual(manifest["fft"]["scale_schedule"], "0x6AB")
        self.assertEqual(manifest["fft"]["total_shift"], 12)
        self.assertEqual(manifest["crc"]["algorithm"], "CRC-32/ISO-HDLC")
        self.assertEqual(manifest["crc"]["word_byte_order"], "little-endian")
        self.assertEqual(set(cases), EXPECTED_CASES)

        required = {
            "nfft",
            "input_file",
            "fft_file",
            "power_file",
            "input_crc32",
            "overflow",
            "search_start",
            "search_stop",
            "dc_guard",
            "peak_bin",
            "peak_re",
            "peak_im",
            "peak_power",
        }
        for case in cases.values():
            self.assertTrue(required.issubset(case))
            self.assertEqual(case["nfft"], 2048)

    def test_hex_payloads_match_manifest_crc_power_and_peak(self) -> None:
        self.assertTrue(MANIFEST_PATH.is_file(), "FFT vector manifest has not been generated")
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

        for case in manifest["cases"]:
            input_words = _read_hex_words(VECTOR_DIR / case["input_file"], np.dtype(np.uint32))
            fft_words = _read_hex_words(VECTOR_DIR / case["fft_file"], np.dtype(np.uint32))
            power_words = _read_hex_words(VECTOR_DIR / case["power_file"], np.dtype(np.uint64))

            self.assertEqual(input_words.size, 2048)
            self.assertEqual(fft_words.size, 2048)
            self.assertEqual(power_words.size, 2048)
            crc = zlib.crc32(input_words.astype("<u4", copy=False).tobytes()) & 0xFFFFFFFF
            self.assertEqual(f"0x{crc:08X}", case["input_crc32"])

            real = (fft_words & 0xFFFF).astype(np.uint16).view(np.int16)
            imag = (fft_words >> 16).astype(np.uint16).view(np.int16)
            calculated_power = real.astype(np.int64) ** 2 + imag.astype(np.int64) ** 2
            np.testing.assert_array_equal(power_words, calculated_power.astype(np.uint64))

            eligible = np.ones(2048, dtype=bool)
            eligible[: case["dc_guard"] + 1] = False
            if case["dc_guard"]:
                eligible[2048 - case["dc_guard"] :] = False
            eligible[: case["search_start"]] = False
            eligible[case["search_stop"] + 1 :] = False
            candidates = np.flatnonzero(eligible)
            peak_bin = int(candidates[np.argmax(power_words[candidates])])

            self.assertEqual(peak_bin, case["peak_bin"])
            self.assertEqual(int(real[peak_bin]), case["peak_re"])
            self.assertEqual(int(imag[peak_bin]), case["peak_im"])
            self.assertEqual(int(power_words[peak_bin]), case["peak_power"])

    def test_hex_files_are_uppercase_fixed_width_with_lf_endings(self) -> None:
        self.assertTrue(MANIFEST_PATH.is_file(), "FFT vector manifest has not been generated")
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

        for case in manifest["cases"]:
            for key, width in (("input_file", 8), ("fft_file", 8), ("power_file", 16)):
                payload = (VECTOR_DIR / case[key]).read_bytes()
                self.assertNotIn(b"\r", payload)
                self.assertTrue(payload.endswith(b"\n"))
                lines = payload.decode("ascii").splitlines()
                self.assertEqual(len(lines), 2048)
                self.assertTrue(all(len(line) == width for line in lines))
                self.assertTrue(all(line == line.upper() for line in lines))
                self.assertTrue(all(set(line) <= set("0123456789ABCDEF") for line in lines))

    def test_guard_and_equal_power_tie_choose_the_lowest_eligible_bin(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cases = {case["name"]: case for case in manifest["cases"]}

        self.assertEqual(cases["impulse"]["dc_guard"], 4)
        self.assertEqual(cases["impulse"]["peak_bin"], 5)

        tie = cases["two_tone_tie"]
        power = _read_hex_words(VECTOR_DIR / tie["power_file"], np.dtype(np.uint64))
        self.assertEqual(int(power[300]), int(power[700]))
        self.assertGreater(int(power[300]), 0)
        self.assertEqual(tie["peak_bin"], 300)


if __name__ == "__main__":
    unittest.main()
