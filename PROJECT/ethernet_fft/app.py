"""Live Matplotlib viewer for continuous AXU4EV FFT-over-UDP frames."""

from __future__ import annotations

import argparse
import time

import matplotlib.pyplot as plt

from PROJECT.ethernet_fft.receiver import ReceiverStats, UdpFftReceiver
from PROJECT.lab_console.model import PlotFrame, SpectrumHistory
from PROJECT.lab_console.protocol import SpectrumResponse


def _non_negative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


class LiveSpectrumView:
    """Own a bounded history and update a single spectrum line in place."""

    def __init__(self, *, history: int = 32) -> None:
        self.history = SpectrumHistory(history=history)
        self.figure, self.spectrum_ax = plt.subplots(figsize=(11, 6))
        (self.spectrum_line,) = self.spectrum_ax.plot([], [], linewidth=1.0)
        self.spectrum_ax.set_title("Live AXU4EV AD9364 FFT over UDP")
        self.spectrum_ax.set_xlabel("RF frequency (MHz)")
        self.spectrum_ax.set_ylabel("relative dB")
        self.status_text = self.figure.text(
            0.01,
            0.01,
            "Waiting for a complete FFT frame",
            family="monospace",
        )
        self.figure.tight_layout(rect=(0, 0.06, 1, 1))

    def accept_response(
        self,
        response: SpectrumResponse,
        stats: ReceiverStats,
        *,
        fps: float,
    ) -> PlotFrame:
        frame = self.history.append(response)
        frequencies_mhz = frame.frequency_hz / 1_000_000.0
        self.spectrum_line.set_data(frequencies_mhz, frame.spectrum_db)
        self.spectrum_ax.set_xlim(
            float(frequencies_mhz[0]), float(frequencies_mhz[-1])
        )
        self.spectrum_ax.set_ylim(-120.0, 3.0)
        self.status_text.set_text(
            f"frame {response.frame_id} | peak bin {response.peak_bin} | "
            f"{frame.peak_frequency_hz / 1e6:.6f} MHz | {fps:.1f} FPS | "
            f"packets {stats.packets_received} | lost {stats.lost_frames} | "
            f"invalid {stats.invalid_datagrams} | "
            f"out-of-order {stats.out_of_order_chunks} | "
            f"duplicates {stats.duplicate_chunks}"
        )
        self.figure.canvas.draw_idle()
        return frame


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Continuous AXU4EV AD9364 Ethernet FFT viewer"
    )
    parser.add_argument("--bind", default="192.168.1.100")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--history", type=int, default=32)
    parser.add_argument(
        "--frames",
        type=_non_negative_int,
        default=0,
        help="0 runs continuously; a positive value is a finite acceptance capture",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    view = LiveSpectrumView(history=args.history)
    plt.show(block=False)
    started_at = time.monotonic()
    displayed = 0
    try:
        with UdpFftReceiver(bind=args.bind, port=args.port) as receiver:
            def on_idle() -> bool:
                plt.pause(0.001)
                return not plt.fignum_exists(view.figure.number)

            for response in receiver.frames(
                limit=args.frames,
                stop=lambda _response: not plt.fignum_exists(view.figure.number),
                on_idle=on_idle,
            ):
                displayed += 1
                elapsed = max(time.monotonic() - started_at, 1e-9)
                view.accept_response(
                    response,
                    receiver.stats,
                    fps=displayed / elapsed,
                )
                plt.pause(0.001)
    except KeyboardInterrupt:
        pass
    finally:
        plt.close(view.figure)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
