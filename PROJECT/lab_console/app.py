"""Matplotlib spectrum/waterfall UI for the bare-metal FFT lab target."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Callable

import matplotlib.pyplot as plt
import numpy as np

from .model import PlotFrame, SpectrumHistory
from .protocol import FFT_SIZE, SpectrumResponse
from .serial_client import CaptureConfig, LabSerialClient
from .storage import CapturePaths, save_capture


SaveCallback = Callable[[PlotFrame], object]


class LabConsoleSession:
    """Own the validated history and its two-panel Matplotlib view."""

    def __init__(
        self,
        *,
        history: int = 32,
        search_start: int = 0,
        search_stop: int = FFT_SIZE - 1,
        save_callback: SaveCallback | None = None,
    ) -> None:
        self.history = SpectrumHistory(
            history=history,
            search_start=search_start,
            search_stop=search_stop,
        )
        self.save_callback = save_callback
        self.current_frame: PlotFrame | None = None
        self.figure, axes = plt.subplots(2, 1, figsize=(11, 8))
        self.spectrum_ax, self.waterfall_ax = axes
        (self.spectrum_line,) = self.spectrum_ax.plot(
            [], [], linewidth=1.0
        )
        (self.peak_marker,) = self.spectrum_ax.plot(
            [], [], "ro", markersize=5
        )
        self.waterfall_image = self.waterfall_ax.imshow(
            np.zeros((1, FFT_SIZE), dtype=np.float64),
            origin="lower",
            aspect="auto",
            interpolation="nearest",
            vmin=-100.0,
            vmax=0.0,
        )
        self.spectrum_ax.set_title(
            "Live FFT spectrum — relative dB, uncalibrated"
        )
        self.spectrum_ax.set_ylabel("relative dB")
        self.waterfall_ax.set_xlabel("RF frequency (MHz)")
        self.waterfall_ax.set_ylabel("valid frame history")
        self.health_text = self.figure.text(
            0.01,
            0.01,
            "Waiting for a CRC-valid frame",
            family="monospace",
        )
        self.figure.tight_layout(rect=(0, 0.05, 1, 1))

    def accept_response(
        self, response: SpectrumResponse
    ) -> PlotFrame | None:
        try:
            frame = self.history.append(response)
        except ValueError as exc:
            self.health_text.set_text(f"REJECTED: {exc}")
            return None

        frequencies_mhz = frame.frequency_hz / 1_000_000.0
        self.spectrum_line.set_data(frequencies_mhz, frame.spectrum_db)
        self.peak_marker.set_data(
            [frame.peak_frequency_hz / 1_000_000.0],
            [frame.peak_relative_db],
        )
        self.spectrum_ax.set_xlim(
            float(frequencies_mhz[0]),
            float(frequencies_mhz[-1]),
        )
        self.spectrum_ax.set_ylim(-120.0, 3.0)

        waterfall = self.history.waterfall_db
        self.waterfall_image.set_data(waterfall)
        self.waterfall_image.set_extent(
            (
                float(frequencies_mhz[0]),
                float(frequencies_mhz[-1]),
                0.0,
                float(max(1, waterfall.shape[0])),
            )
        )
        self.waterfall_ax.set_xlim(
            float(frequencies_mhz[0]),
            float(frequencies_mhz[-1]),
        )
        self.waterfall_ax.set_ylim(0.0, float(max(1, waterfall.shape[0])))
        self.health_text.set_text(
            "CRC OK | "
            f"frame {response.frame_id} | seq {response.sequence} | "
            f"RF state {response.rf_state} | bank {response.active_bank} | "
            f"LO {response.lo_hz / 1e6:.6f} MHz | "
            f"Fs {response.sample_rate_hz / 1e6:.3f} MSPS | "
            f"BW {response.rx_bandwidth_hz / 1e6:.3f} MHz | "
            f"flags 0x{response.hardware_flags:04x}"
        )
        self.current_frame = frame
        self.figure.canvas.draw_idle()
        return frame

    def save_current(self) -> object:
        if self.current_frame is None:
            raise RuntimeError("no valid frame is available to save")
        if self.save_callback is None:
            raise RuntimeError("no save callback is configured")
        return self.save_callback(self.current_frame)


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="AXU4EVB-P AD9364 bare-metal FFT lab console"
    )
    parser.add_argument("--port", required=True, help="PS_UART COM port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--interval-ms", type=int, default=250)
    parser.add_argument("--history", type=int, default=32)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("PROJECT/lab-captures"),
    )
    parser.add_argument("--search-start", type=int, default=0)
    parser.add_argument("--search-stop", type=int, default=2047)
    parser.add_argument("--dc-guard", type=int, default=0)
    parser.add_argument("--rf-state", type=int, default=0)
    parser.add_argument("--single", action="store_true")
    return parser


def _print_capture(paths: CapturePaths) -> None:
    print(f"Saved NPZ: {paths.npz}")
    print(f"Saved CSV: {paths.csv}")


def main(argv: list[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    if args.interval_ms < 0:
        raise ValueError("interval-ms must be non-negative")
    config = CaptureConfig(
        search_start=args.search_start,
        search_stop=args.search_stop,
        dc_guard=args.dc_guard,
        rf_state=args.rf_state,
    )

    with LabSerialClient(args.port, baud=args.baud) as client:
        info = client.get_info()

        def save_frame(frame: PlotFrame) -> CapturePaths:
            paths = save_capture(
                args.output_dir,
                frame,
                info.release_id,
            )
            _print_capture(paths)
            return paths

        session = LabConsoleSession(
            history=args.history,
            search_start=args.search_start,
            search_stop=args.search_stop,
            save_callback=save_frame,
        )
        if args.single:
            frame = session.accept_response(client.capture_once(config))
            if frame is None:
                return 2
            session.save_current()
            plt.close(session.figure)
            return 0

        from matplotlib.animation import FuncAnimation

        def update(_frame_number: int) -> tuple[object, ...]:
            session.accept_response(client.capture_once(config))
            return (
                session.spectrum_line,
                session.peak_marker,
                session.waterfall_image,
                session.health_text,
            )

        def on_key(event: object) -> None:
            if getattr(event, "key", None) == "s":
                session.save_current()

        session.figure.canvas.mpl_connect("key_press_event", on_key)
        animation = FuncAnimation(
            session.figure,
            update,
            interval=args.interval_ms,
            blit=False,
            cache_frame_data=False,
        )
        setattr(session, "_animation", animation)
        plt.show()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
