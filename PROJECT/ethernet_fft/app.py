"""Live Matplotlib viewer for continuous AXU4EV FFT-over-UDP frames."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from typing import Callable, Protocol

import matplotlib.pyplot as plt

from PROJECT.ethernet_fft.receiver import ReceiverStats, UdpFftReceiver
from PROJECT.lab_console.model import PlotFrame, SpectrumHistory
from PROJECT.lab_console.protocol import SpectrumResponse


def _non_negative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return parsed


class _FrameReceiver(Protocol):
    @property
    def stats(self) -> ReceiverStats: ...

    def frames(self, *, limit: int, stop: Callable[[SpectrumResponse], bool] | None,
               on_idle: Callable[[], bool] | None): ...


def capture_headless(
    receiver: _FrameReceiver,
    *,
    frame_limit: int,
    duration_seconds: int,
    clock: Callable[[], float] = time.monotonic,
) -> dict[str, int | float | str | None]:
    """Capture frames without a GUI and return a JSON-ready transport summary."""

    started_at = clock()
    frame_ids: list[int] = []

    def duration_reached() -> bool:
        return duration_seconds > 0 and clock() - started_at >= duration_seconds

    for response in receiver.frames(
        limit=frame_limit,
        stop=(lambda _response: duration_reached()) if duration_seconds else None,
        on_idle=duration_reached if duration_seconds else None,
    ):
        frame_ids.append(response.frame_id)

    elapsed_seconds = round(max(clock() - started_at, 0.0), 6)
    stats = receiver.stats
    if duration_seconds and elapsed_seconds >= duration_seconds:
        stop_reason = "duration"
    elif frame_limit and len(frame_ids) >= frame_limit:
        stop_reason = "frame_limit"
    else:
        stop_reason = "source_exhausted"
    first_frame_id = frame_ids[0] if frame_ids else None
    last_frame_id = frame_ids[-1] if frame_ids else None
    return {
        "requested_frames": frame_limit,
        "duration_seconds": duration_seconds,
        "elapsed_seconds": elapsed_seconds,
        "stop_reason": stop_reason,
        "completed_frames": len(frame_ids),
        "first_frame_id": first_frame_id,
        "last_frame_id": last_frame_id,
        "frame_id_span": (
            last_frame_id - first_frame_id
            if first_frame_id is not None and last_frame_id is not None
            else None
        ),
        "packets_received": stats.packets_received,
        "lost_frames": stats.lost_frames,
        "invalid_datagrams": stats.invalid_datagrams,
        "duplicate_chunks": stats.duplicate_chunks,
        "out_of_order_chunks": stats.out_of_order_chunks,
    }


def write_capture_evidence(
    capture: dict[str, int | float | str | None],
    *,
    evidence_dir: Path,
    captured_at: str | None = None,
) -> Path:
    """Persist a capture summary as machine-readable local-run evidence."""

    captured_at = captured_at or datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    timestamp = captured_at.replace("-", "").replace(":", "").replace("Z", "")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = evidence_dir / f"axu4ev-ad9364-ethernet-capture-{timestamp}Z.json"
    payload = {"schema_version": 1, "captured_at_utc": captured_at, **capture}
    evidence_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return evidence_path


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
    parser.add_argument(
        "--duration-seconds",
        type=_non_negative_int,
        default=0,
        help="0 has no time limit; a positive value stops a headless capture by time",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="capture without opening the live Matplotlib viewer",
    )
    parser.add_argument(
        "--evidence-dir",
        type=Path,
        help="directory in which to write a JSON capture summary",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    if args.headless:
        with UdpFftReceiver(bind=args.bind, port=args.port) as receiver:
            capture = capture_headless(
                receiver,
                frame_limit=args.frames,
                duration_seconds=args.duration_seconds,
            )
        if args.evidence_dir is not None:
            evidence_path = write_capture_evidence(
                capture, evidence_dir=args.evidence_dir
            )
            print(f"ETH_FFT: evidence={evidence_path}")
        complete = (
            args.frames > 0
            and capture["completed_frames"] == args.frames
            and capture["lost_frames"] == 0
            and capture["invalid_datagrams"] == 0
        )
        if args.frames > 0:
            status = "PASS" if complete else "FAIL"
        else:
            status = "COMPLETE"
        print(
            f"ETH_FFT: {status} frames={capture['completed_frames']} "
            f"last_frame={capture['last_frame_id']} "
            f"lost_frames={capture['lost_frames']} "
            f"invalid_datagrams={capture['invalid_datagrams']}"
        )
        return 0 if status != "FAIL" else 1
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
