import csv
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from PROJECT.lab_console.model import SpectrumHistory
from PROJECT.lab_console.storage import save_capture
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


if __name__ == "__main__":
    unittest.main()
