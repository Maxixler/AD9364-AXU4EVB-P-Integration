import csv
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from PROJECT.lab_console.model import SpectrumHistory
from PROJECT.lab_console.storage import save_capture, save_capture_series
from PROJECT.tests.test_lab_console_model import make_response


class CaptureStorageTests(unittest.TestCase):
    def test_npz_and_csv_save_the_same_exact_frame(self) -> None:
        spectrum = np.arange(2048, dtype=np.uint64)
        spectrum[77] = 100_000
        frame = SpectrumHistory(history=32).append(
            make_response(spectrum, frame_id=41, peak_bin=77)
        )
        captured_at = datetime(
            2026, 7, 27, 12, 34, 56, 123456, tzinfo=timezone.utc
        )

        with tempfile.TemporaryDirectory() as temporary:
            paths = save_capture(
                Path(temporary),
                frame,
                "monopulse-live-lab-v1",
                captured_at=captured_at,
            )

            with np.load(paths.npz) as saved:
                self.assertEqual(saved["spectrum"].dtype, np.uint64)
                self.assertEqual(saved["spectrum"].shape, (2048,))
                np.testing.assert_array_equal(
                    saved["spectrum"], frame.natural_spectrum
                )
                np.testing.assert_array_equal(
                    saved["frequency_hz"], frame.frequency_hz
                )
                self.assertEqual(int(saved["frame_id"]), 41)
                self.assertEqual(
                    str(saved["release_id"]),
                    "monopulse-live-lab-v1",
                )

            with paths.csv.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["frame_id"], "41")
            self.assertEqual(rows[0]["npz_file"], paths.npz.name)
            self.assertEqual(
                rows[0]["release_id"], "monopulse-live-lab-v1"
            )
            self.assertEqual(rows[0]["peak_bin"], "77")
            self.assertEqual(list(Path(temporary).glob("*.tmp")), [])

    def test_collision_uses_a_suffix_without_overwriting(self) -> None:
        spectrum = np.zeros(2048, dtype=np.uint64)
        spectrum[5] = 1
        frame = SpectrumHistory(history=32).append(
            make_response(spectrum, frame_id=9, peak_bin=5)
        )
        captured_at = datetime(
            2026, 7, 27, 12, 0, 0, tzinfo=timezone.utc
        )

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            first = save_capture(
                output,
                frame,
                "monopulse-live-lab-v1",
                captured_at=captured_at,
            )
            first_npz = first.npz.read_bytes()
            first_csv = first.csv.read_bytes()
            second = save_capture(
                output,
                frame,
                "monopulse-live-lab-v1",
                captured_at=captured_at,
            )

            self.assertNotEqual(first.npz, second.npz)
            self.assertNotEqual(first.csv, second.csv)
            self.assertEqual(first.npz.read_bytes(), first_npz)
            self.assertEqual(first.csv.read_bytes(), first_csv)
            self.assertTrue(second.npz.exists())
            self.assertTrue(second.csv.exists())
            self.assertEqual(list(output.glob("*.tmp")), [])

    def test_series_saves_ten_exact_frames_for_cw_validation(self) -> None:
        frames = []
        for index, peak_bin in enumerate(
            (122, 123, 124, 123, 122, 124, 123, 123, 122, 124)
        ):
            spectrum = np.ones(2048, dtype=np.uint64)
            spectrum[peak_bin] = 100_000 + index
            frames.append(
                SpectrumHistory(history=32).append(
                    make_response(
                        spectrum,
                        frame_id=100 + index,
                        peak_bin=peak_bin,
                    )
                )
            )

        with tempfile.TemporaryDirectory() as temporary:
            paths = save_capture_series(
                Path(temporary),
                frames,
                "monopulse-live-lab-v1",
                base_name="axu4ev-ad9364-live-lab-cw",
                captured_at=datetime(
                    2026, 7, 27, 15, 0, 0, tzinfo=timezone.utc
                ),
            )
            with np.load(paths.npz) as saved:
                self.assertEqual(saved["spectrum"].shape, (10, 2048))
                self.assertEqual(saved["spectrum"].dtype, np.uint64)
                np.testing.assert_array_equal(
                    saved["frame_id"], np.arange(100, 110)
                )
                np.testing.assert_array_equal(
                    saved["protocol_crc_valid"], np.ones(10)
                )
                self.assertEqual(
                    paths.npz.name,
                    "axu4ev-ad9364-live-lab-cw-capture.npz",
                )
            with paths.csv.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 10)
            self.assertEqual(rows[0]["frame_id"], "100")
            self.assertEqual(rows[-1]["frame_id"], "109")
            self.assertEqual(
                paths.csv.name,
                "axu4ev-ad9364-live-lab-cw-summary.csv",
            )

            with self.assertRaises(FileExistsError):
                save_capture_series(
                    Path(temporary),
                    frames,
                    "monopulse-live-lab-v1",
                    base_name="axu4ev-ad9364-live-lab-cw",
                )


if __name__ == "__main__":
    unittest.main()
