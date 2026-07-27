import unittest

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from PROJECT.lab_console.app import LabConsoleSession
from PROJECT.tests.test_lab_console_model import make_response


class LabConsoleViewTests(unittest.TestCase):
    def tearDown(self) -> None:
        plt.close("all")

    def test_valid_frame_updates_spectrum_peak_waterfall_and_health(
        self,
    ) -> None:
        session = LabConsoleSession(history=32)
        spectrum = np.zeros(2048, dtype=np.uint64)
        spectrum[5] = 1234

        frame = session.accept_response(
            make_response(spectrum, frame_id=9, peak_bin=5)
        )

        self.assertIsNotNone(frame)
        self.assertIsNotNone(session.spectrum_ax)
        self.assertIsNotNone(session.waterfall_ax)
        self.assertEqual(len(session.figure.axes), 2)
        self.assertIn(
            "relative dB, uncalibrated",
            session.spectrum_ax.get_title(),
        )
        self.assertEqual(
            float(session.peak_marker.get_xdata()[0]),
            frame.peak_frequency_hz / 1_000_000.0,
        )
        self.assertEqual(session.history.waterfall_db.shape, (1, 2048))
        self.assertIn("CRC OK", session.health_text.get_text())
        self.assertIn("RF state 0", session.health_text.get_text())
        self.assertIn("frame 9", session.health_text.get_text())

    def test_fatal_frame_does_not_enter_waterfall(self) -> None:
        session = LabConsoleSession(history=32)
        spectrum = np.zeros(2048, dtype=np.uint64)
        spectrum[5] = 1234
        session.accept_response(
            make_response(spectrum, frame_id=1, peak_bin=5)
        )

        result = session.accept_response(
            make_response(
                spectrum,
                frame_id=2,
                peak_bin=5,
                hardware_flags=1,
            )
        )

        self.assertIsNone(result)
        self.assertEqual(len(session.history), 1)
        self.assertEqual(session.history.waterfall_db.shape, (1, 2048))
        self.assertIn("REJECTED", session.health_text.get_text())

    def test_save_current_invokes_callback_with_displayed_frame(self) -> None:
        saved = []
        session = LabConsoleSession(
            history=32,
            save_callback=saved.append,
        )
        spectrum = np.zeros(2048, dtype=np.uint64)
        spectrum[5] = 1234
        frame = session.accept_response(
            make_response(spectrum, frame_id=3, peak_bin=5)
        )

        session.save_current()

        self.assertEqual(saved, [frame])


if __name__ == "__main__":
    unittest.main()
