"""Contract tests for the installed Xilinx FFT v9.1 bit-accurate model."""

from pathlib import Path
import unittest

import numpy as np

try:
    from PROJECT.verification.fft.model import xilinx_fft_cmodel
except ModuleNotFoundError:
    FftResult = None
    decode_scale_schedule = None
    discover_xfft_library = None
    simulate_fft = None
    model_output_to_q15 = None
else:
    FftResult = getattr(xilinx_fft_cmodel, "FftResult", None)
    decode_scale_schedule = getattr(xilinx_fft_cmodel, "decode_scale_schedule", None)
    discover_xfft_library = getattr(xilinx_fft_cmodel, "discover_xfft_library", None)
    simulate_fft = getattr(xilinx_fft_cmodel, "simulate_fft", None)
    model_output_to_q15 = getattr(xilinx_fft_cmodel, "_model_output_to_q15", None)


class XilinxFftCModelContractTests(unittest.TestCase):
    @staticmethod
    def _complex_tone(bin_index: int, amplitude: int) -> tuple[np.ndarray, np.ndarray]:
        samples = np.arange(2048)
        phase = 2.0 * np.pi * bin_index * samples / 2048
        return (
            np.rint(amplitude * np.cos(phase)).astype(np.int16),
            np.rint(amplitude * np.sin(phase)).astype(np.int16),
        )

    def test_decodes_streaming_schedule_from_least_significant_stage(self) -> None:
        self.assertIsNotNone(
            decode_scale_schedule,
            "FFT C-model wrapper API has not been implemented",
        )

        schedule = decode_scale_schedule(0x6AB, nfft=11)

        self.assertEqual(schedule, (3, 2, 2, 2, 2, 1))
        self.assertEqual(sum(schedule), 12)

    def test_discovers_the_vivado_2020_1_fft_library(self) -> None:
        self.assertIsNotNone(
            discover_xfft_library,
            "FFT C-model wrapper API has not been implemented",
        )

        library = discover_xfft_library()

        self.assertIsInstance(library, Path)
        self.assertTrue(library.is_file())
        self.assertEqual(library.name, "libIp_xfft_v9_1_bitacc_cmodel.dll")

    def test_zero_frame_returns_signed_int16_zeros_without_overflow(self) -> None:
        self.assertIsNotNone(simulate_fft, "FFT simulation API has not been implemented")

        samples = np.zeros(2048, dtype=np.int16)
        result = simulate_fft(samples, samples)

        self.assertIsInstance(result, FftResult)
        self.assertEqual(result.real.dtype, np.dtype(np.int16))
        self.assertEqual(result.imag.dtype, np.dtype(np.int16))
        np.testing.assert_array_equal(result.real, samples)
        np.testing.assert_array_equal(result.imag, samples)
        self.assertFalse(result.overflow)

    def test_rejects_non_2048_frames_and_out_of_range_samples(self) -> None:
        self.assertIsNotNone(simulate_fft, "FFT simulation API has not been implemented")

        with self.assertRaisesRegex(ValueError, "exactly 2048"):
            simulate_fft(np.zeros(32, dtype=np.int16), np.zeros(32, dtype=np.int16))

        out_of_range = np.zeros(2048, dtype=np.int64)
        out_of_range[0] = 32768
        with self.assertRaisesRegex(ValueError, "signed 16-bit"):
            simulate_fft(out_of_range, np.zeros(2048, dtype=np.int16))

    def test_impulse_and_complex_tones_have_exact_natural_order_results(self) -> None:
        impulse = np.zeros(2048, dtype=np.int16)
        impulse[0] = 32767
        impulse_result = simulate_fft(impulse, np.zeros_like(impulse))
        np.testing.assert_array_equal(impulse_result.real, np.full(2048, 8, np.int16))
        np.testing.assert_array_equal(impulse_result.imag, np.zeros(2048, np.int16))

        for bin_index in (137, 1901):
            i_samples, q_samples = self._complex_tone(bin_index, amplitude=4096)
            result = simulate_fft(i_samples, q_samples)
            power = result.real.astype(np.int64) ** 2 + result.imag.astype(np.int64) ** 2

            self.assertEqual(int(np.argmax(power)), bin_index)
            self.assertEqual((int(result.real[bin_index]), int(result.imag[bin_index])), (2048, 0))
            self.assertEqual(int(power[bin_index]), 4_194_304)
            self.assertEqual(int(np.count_nonzero(power)), 1)
            self.assertFalse(result.overflow)

    def test_near_full_scale_tone_is_repeatable_without_overflow(self) -> None:
        i_samples, q_samples = self._complex_tone(137, amplitude=32767)

        first = simulate_fft(i_samples, q_samples)
        second = simulate_fft(i_samples, q_samples)

        np.testing.assert_array_equal(first.real, second.real)
        np.testing.assert_array_equal(first.imag, second.imag)
        self.assertEqual((int(first.real[137]), int(first.imag[137])), (16384, 0))
        self.assertFalse(first.overflow)

    def test_rejects_illegal_streaming_scaling_schedules(self) -> None:
        samples = np.zeros(2048, dtype=np.int16)

        with self.assertRaisesRegex(ValueError, "six stages"):
            simulate_fft(samples, samples, scale_schedule=0x16AB)
        with self.assertRaisesRegex(ValueError, "final stage"):
            simulate_fft(samples, samples, scale_schedule=0xEAB)

    def test_requires_model_outputs_to_lie_exactly_on_the_q15_grid(self) -> None:
        self.assertIsNotNone(
            model_output_to_q15,
            "model-output Q1.15 validation has not been implemented",
        )

        converted = model_output_to_q15(
            np.array([-1.0, 0.0, 32767.0 / 32768.0]), "real"
        )
        np.testing.assert_array_equal(
            converted, np.array([-32768, 0, 32767], dtype=np.int16)
        )

        with self.assertRaisesRegex(RuntimeError, "Q1.15 grid"):
            model_output_to_q15(np.array([0.1]), "real")


if __name__ == "__main__":
    unittest.main()
