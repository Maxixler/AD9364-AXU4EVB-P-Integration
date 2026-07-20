"""Deterministic tests for the NumPy monopulse reference and IIO adapter."""

import importlib
import sys
import types
import unittest
from unittest.mock import patch

import numpy as np

from PROJECT.reference.monopulse_reference import (
    find_common_peak,
    integrate_band,
    integrate_cw,
    normalized_errors,
    spectra_from_frames,
)


FFT_SIZE = 2048


def bin_tone(bin_index: int, power: float) -> np.ndarray:
    samples = np.arange(FFT_SIZE)
    return np.sqrt(power) * np.exp(2j * np.pi * bin_index * samples / FFT_SIZE)


def q31_nearest_even(value: float) -> int:
    return int(np.clip(np.rint(value * (1 << 31)), -(1 << 31), (1 << 31) - 1))


class MonopulseReferenceTests(unittest.TestCase):
    def test_common_peak_cw_and_normalized_errors_for_four_tones(self) -> None:
        frames = np.stack([bin_tone(100, power) for power in (300, 100, 100, 300)])

        spectra = spectra_from_frames(frames)
        peak_bin, peak_power = find_common_peak(spectra, (8, 1023), dc_guard=4)
        powers = integrate_cw(spectra, peak_bin)
        az_error, el_error = normalized_errors(powers, denominator_threshold=1.0)

        self.assertEqual(peak_bin, 100)
        self.assertGreater(peak_power, 0.0)
        self.assertAlmostEqual(az_error, 0.5, places=12)
        self.assertAlmostEqual(el_error, -0.5, places=12)
        self.assertEqual(q31_nearest_even(az_error), 1073741824)
        self.assertEqual(q31_nearest_even(el_error), -1073741824)
        print("CROSSCHECK powers=300,100,100,300 q31=1073741824,-1073741824")

    def test_dc_guard_excludes_dc_but_keeps_guard_boundary(self) -> None:
        spectra = np.zeros((4, FFT_SIZE), dtype=float)
        spectra[0, 3] = 1000.0
        spectra[0, 4] = 101.0
        spectra[:, 100] = (10.0, 20.0, 30.0, 40.0)

        peak_bin, peak_power = find_common_peak(spectra, (0, 101), dc_guard=4)

        self.assertEqual((peak_bin, peak_power), (4, 101.0))

    def test_common_peak_uses_lower_bin_when_totals_tie(self) -> None:
        spectra = np.zeros((4, FFT_SIZE), dtype=float)
        spectra[:, 100] = (10.0, 20.0, 30.0, 40.0)
        spectra[:, 101] = (1.0, 2.0, 3.0, 94.0)

        self.assertEqual(find_common_peak(spectra, (8, 1023), dc_guard=4), (100, 100.0))

    def test_off_bin_tone_keeps_its_common_peak(self) -> None:
        frames = np.stack([bin_tone(123, power) for power in (1, 2, 3, 4)])
        spectra = spectra_from_frames(frames)

        self.assertEqual(find_common_peak(spectra, (8, 1023), dc_guard=4)[0], 123)

    def test_cw_and_band_intervals_are_inclusive(self) -> None:
        spectra = np.zeros((4, FFT_SIZE), dtype=float)
        spectra[:, 98:103] = np.array([[1, 2, 10, 4, 5], [2, 3, 20, 5, 6], [3, 4, 30, 6, 7], [4, 5, 40, 7, 8]])
        band_spectra = np.zeros((4, FFT_SIZE), dtype=float)
        band_spectra[:, 64] = (1, 3, 7, 13)
        band_spectra[:, 65] = (2, 0, 0, 0)
        band_spectra[:, 511] = (4, 5, 11, 17)

        np.testing.assert_array_equal(integrate_cw(spectra, 100), (22.0, 36.0, 50.0, 64.0))
        np.testing.assert_array_equal(integrate_band(band_spectra, (64, 511)), (7.0, 8.0, 18.0, 30.0))

    def test_denominator_threshold_invalidates_an_axis(self) -> None:
        with self.assertRaises(ValueError):
            normalized_errors(np.array([2.0, 1.0, 1.0, 1.0]), denominator_threshold=4.0)

    def test_q31_cross_check_uses_python_nearest_even_rounding(self) -> None:
        self.assertEqual(q31_nearest_even(1 / 3), 715827883)
        self.assertEqual(q31_nearest_even(-1 / 3), -715827883)
        self.assertEqual(q31_nearest_even(0.5 / (1 << 31)), 0)
        self.assertEqual(q31_nearest_even(1.5 / (1 << 31)), 2)
        self.assertEqual(q31_nearest_even(-1.5 / (1 << 31)), -2)

    def test_rejects_wrong_shapes_nonfinite_values_and_invalid_ranges(self) -> None:
        frames = np.zeros((4, FFT_SIZE), dtype=np.complex128)
        spectra = np.zeros((4, FFT_SIZE), dtype=float)
        with self.assertRaises(ValueError):
            spectra_from_frames(np.zeros((3, FFT_SIZE)))
        frames[0, 0] = np.nan
        with self.assertRaises(ValueError):
            spectra_from_frames(frames)
        spectra[0, 0] = np.inf
        with self.assertRaises(ValueError):
            find_common_peak(spectra, (8, 1023), dc_guard=4)
        with self.assertRaises(ValueError):
            find_common_peak(np.zeros((4, FFT_SIZE)), (9, 8), dc_guard=4)
        with self.assertRaises(ValueError):
            integrate_cw(np.zeros((4, FFT_SIZE)), 1)
        with self.assertRaises(ValueError):
            integrate_band(np.zeros((4, FFT_SIZE)), (512, 511))
        with self.assertRaises(ValueError):
            normalized_errors(np.array([1.0, 1.0, 1.0, np.nan]), 1.0)


class CaptureAdapterTests(unittest.TestCase):
    def test_capture_configures_ad936x_rx_and_returns_one_complex_vector(self) -> None:
        class FakeAd9361:
            instance = None

            def __init__(self, *, uri: str) -> None:
                self.uri = uri
                self.rx_enabled_channels = None
                FakeAd9361.instance = self

            def rx(self) -> np.ndarray:
                return np.arange(FFT_SIZE, dtype=np.float64).astype(np.complex128)

        fake_adi = types.SimpleNamespace(ad9361=FakeAd9361)
        with patch.dict(sys.modules, {"adi": fake_adi}):
            sys.modules.pop("PROJECT.tools.capture_monopulse_iio", None)
            adapter = importlib.import_module("PROJECT.tools.capture_monopulse_iio")
            captured = adapter.capture_ad936x("ip:192.0.2.1", 30_720_000, 10_000_000, 2_450_000_000, 17.5, FFT_SIZE)

        self.assertEqual(captured.shape, (FFT_SIZE,))
        self.assertTrue(np.iscomplexobj(captured))
        device = FakeAd9361.instance
        self.assertEqual(device.uri, "ip:192.0.2.1")
        self.assertEqual(device.rx_enabled_channels, [0])
        self.assertEqual(device.sample_rate, 30_720_000)
        self.assertEqual(device.rx_rf_bandwidth, 10_000_000)
        self.assertEqual(device.rx_lo, 2_450_000_000)
        self.assertEqual(device.gain_control_mode_chan0, "manual")
        self.assertEqual(device.rx_hardwaregain_chan0, 17.5)
        self.assertEqual(device.rx_buffer_size, FFT_SIZE)

    def test_capture_translates_missing_pyadi_iio_to_hard_iio_gate(self) -> None:
        with patch.dict(sys.modules, {"adi": None}):
            sys.modules.pop("PROJECT.tools.capture_monopulse_iio", None)
            adapter = importlib.import_module("PROJECT.tools.capture_monopulse_iio")
            with self.assertRaisesRegex(RuntimeError, "^pyadi-iio requires a reachable Linux/IIOD IIO context$"):
                adapter.capture_ad936x("ip:192.0.2.1", 30_720_000, 10_000_000, 2_450_000_000, 17.5, FFT_SIZE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
