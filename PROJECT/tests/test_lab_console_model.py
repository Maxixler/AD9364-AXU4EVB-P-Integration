import unittest

import numpy as np

from PROJECT.lab_console.model import (
    SpectrumHistory,
    centered_frequency_axis,
    centered_natural_indices,
    relative_db,
)
from PROJECT.lab_console.protocol import SpectrumResponse


def make_response(
    spectrum: np.ndarray,
    *,
    frame_id: int = 1,
    peak_bin: int | None = None,
    hardware_flags: int = 0,
    gain_db: int = 50,
) -> SpectrumResponse:
    values = np.asarray(spectrum, dtype=np.uint64)
    if peak_bin is None:
        peak_bin = int(np.argmax(values))
    return SpectrumResponse(
        sequence=frame_id + 100,
        frame_id=frame_id,
        sample_count=values.size,
        fft_size=values.size,
        sample_rate_hz=30_720_000,
        rx_bandwidth_hz=10_000_000,
        lo_hz=2_400_000_000,
        frame_crc32=0xAABBCCDD,
        skipped_sample_count=12,
        peak_power=int(values[peak_bin]),
        peak_bin=peak_bin,
        peak_re=-123,
        peak_im=456,
        reset_epoch=3,
        rf_state=0,
        active_bank=1,
        hardware_flags=hardware_flags,
        gain_db=gain_db,
        gain_mode=0,
        spectrum=values,
    )


class FrequencyModelTests(unittest.TestCase):
    def test_centered_axis_and_natural_bin_order_are_exact(self) -> None:
        expected_axis = (
            np.array([96, 97, 98, 99, 100, 101, 102, 103])
            * 1_000_000
        )

        np.testing.assert_array_equal(
            centered_frequency_axis(100_000_000, 8_000_000, 8),
            expected_axis,
        )
        np.testing.assert_array_equal(
            centered_natural_indices(8),
            np.array([4, 5, 6, 7, 0, 1, 2, 3]),
        )

    def test_relative_db_is_peak_normalized_and_has_a_finite_floor(self) -> None:
        values = np.array([0, 1, 10, 100], dtype=np.uint64)

        result = relative_db(values)

        np.testing.assert_allclose(result[1:], [-20.0, -10.0, 0.0])
        self.assertEqual(result[0], -300.0)
        self.assertTrue(np.all(np.isfinite(result)))


class SpectrumHistoryTests(unittest.TestCase):
    def test_append_centers_an_immutable_copy_and_peak_frequency(self) -> None:
        natural = np.zeros(2048, dtype=np.uint64)
        natural[1536] = 900
        history = SpectrumHistory(history=32)

        frame = history.append(make_response(natural, peak_bin=1536))
        natural[1536] = 0

        self.assertEqual(frame.peak_frequency_hz, 2_392_320_000)
        self.assertEqual(frame.peak_relative_db, 0.0)
        self.assertEqual(int(frame.natural_spectrum[1536]), 900)
        self.assertFalse(frame.natural_spectrum.flags.writeable)
        self.assertFalse(frame.centered_spectrum.flags.writeable)
        self.assertEqual(frame.centered_spectrum.shape, (2048,))
        self.assertEqual(len(history), 1)

    def test_peak_mismatch_uses_lower_index_tie_and_does_not_enter_history(
        self,
    ) -> None:
        natural = np.zeros(2048, dtype=np.uint64)
        natural[20] = 99
        natural[21] = 99
        history = SpectrumHistory(
            history=32,
            search_start=10,
            search_stop=30,
        )

        with self.assertRaisesRegex(ValueError, "peak_bin"):
            history.append(make_response(natural, peak_bin=21))

        self.assertEqual(len(history), 0)

    def test_fatal_frame_is_rejected_before_waterfall(self) -> None:
        natural = np.zeros(2048, dtype=np.uint64)
        natural[4] = 1
        history = SpectrumHistory(history=32)

        with self.assertRaisesRegex(ValueError, "hardware"):
            history.append(
                make_response(natural, peak_bin=4, hardware_flags=1)
            )

        self.assertEqual(len(history), 0)

    def test_history_retains_only_the_latest_32_frames(self) -> None:
        natural = np.zeros(2048, dtype=np.uint64)
        natural[4] = 1
        history = SpectrumHistory(history=32)

        for frame_id in range(1, 34):
            history.append(
                make_response(natural, frame_id=frame_id, peak_bin=4)
            )

        self.assertEqual(len(history), 32)
        self.assertEqual(history.frames[0].response.frame_id, 2)
        self.assertEqual(history.frames[-1].response.frame_id, 33)
        self.assertEqual(history.waterfall_db.shape, (32, 2048))

    def test_gain_change_is_rejected_before_entering_history(self) -> None:
        natural = np.zeros(2048, dtype=np.uint64)
        natural[4] = 1
        history = SpectrumHistory(history=32)
        history.append(make_response(natural, frame_id=1, peak_bin=4))

        with self.assertRaisesRegex(ValueError, "gain"):
            history.append(
                make_response(
                    natural,
                    frame_id=2,
                    peak_bin=4,
                    gain_db=49,
                )
            )

        self.assertEqual(len(history), 1)


if __name__ == "__main__":
    unittest.main()
