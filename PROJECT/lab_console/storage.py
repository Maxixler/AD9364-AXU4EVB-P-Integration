"""Atomic persistence for the exact frame currently shown by the UI."""

from __future__ import annotations

import csv
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from .model import PlotFrame


@dataclass(frozen=True)
class CapturePaths:
    npz: Path
    csv: Path


def _capture_base(captured_at: datetime, frame_id: int) -> str:
    stamp = captured_at.strftime("%Y%m%dT%H%M%S.%fZ")
    return f"{stamp}-frame{frame_id:08d}"


def _unused_pair(output_dir: Path, base: str) -> CapturePaths:
    suffix = 0
    while True:
        candidate = base if suffix == 0 else f"{base}-{suffix}"
        paths = CapturePaths(
            npz=output_dir / f"{candidate}.npz",
            csv=output_dir / f"{candidate}.csv",
        )
        if not paths.npz.exists() and not paths.csv.exists():
            return paths
        suffix += 1


def _flush_and_sync(handle: object) -> None:
    handle.flush()
    os.fsync(handle.fileno())


def save_capture(
    output_dir: Path,
    frame: PlotFrame,
    release_id: str,
    *,
    captured_at: datetime | None = None,
) -> CapturePaths:
    """Save one immutable plot frame without overwriting earlier captures."""

    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    if not release_id or not release_id.isascii():
        raise ValueError("release_id must be non-empty ASCII")
    instant = captured_at or datetime.now(timezone.utc)
    if instant.tzinfo is None or instant.utcoffset() is None:
        raise ValueError("captured_at must be timezone-aware")
    instant = instant.astimezone(timezone.utc)
    response = frame.response
    paths = _unused_pair(
        destination,
        _capture_base(instant, response.frame_id),
    )
    npz_temporary = paths.npz.with_suffix(".npz.tmp")
    csv_temporary = paths.csv.with_suffix(".csv.tmp")

    try:
        with npz_temporary.open("xb") as handle:
            np.savez(
                handle,
                spectrum=frame.natural_spectrum,
                centered_spectrum=frame.centered_spectrum,
                frequency_hz=frame.frequency_hz,
                relative_db=frame.spectrum_db,
                sequence=np.uint32(response.sequence),
                frame_id=np.uint32(response.frame_id),
                sample_count=np.uint16(response.sample_count),
                fft_size=np.uint16(response.fft_size),
                sample_rate_hz=np.uint32(response.sample_rate_hz),
                rx_bandwidth_hz=np.uint32(response.rx_bandwidth_hz),
                lo_hz=np.uint64(response.lo_hz),
                frame_crc32=np.uint32(response.frame_crc32),
                skipped_sample_count=np.uint32(
                    response.skipped_sample_count
                ),
                peak_power=np.uint64(response.peak_power),
                peak_bin=np.uint16(response.peak_bin),
                peak_re=np.int16(response.peak_re),
                peak_im=np.int16(response.peak_im),
                reset_epoch=np.uint16(response.reset_epoch),
                rf_state=np.uint8(response.rf_state),
                active_bank=np.uint8(response.active_bank),
                hardware_flags=np.uint16(response.hardware_flags),
                peak_frequency_hz=np.float64(frame.peak_frequency_hz),
                peak_relative_db=np.float64(frame.peak_relative_db),
                release_id=np.str_(release_id),
                captured_utc=np.str_(instant.isoformat()),
            )
            _flush_and_sync(handle)

        fields = {
            "captured_utc": instant.isoformat(),
            "release_id": release_id,
            "frame_id": response.frame_id,
            "sequence": response.sequence,
            "npz_file": paths.npz.name,
            "lo_hz": response.lo_hz,
            "sample_rate_hz": response.sample_rate_hz,
            "rx_bandwidth_hz": response.rx_bandwidth_hz,
            "rf_state": response.rf_state,
            "active_bank": response.active_bank,
            "reset_epoch": response.reset_epoch,
            "frame_crc32": f"{response.frame_crc32:08x}",
            "hardware_flags": f"{response.hardware_flags:04x}",
            "skipped_sample_count": response.skipped_sample_count,
            "peak_bin": response.peak_bin,
            "peak_frequency_hz": f"{frame.peak_frequency_hz:.6f}",
            "peak_power": response.peak_power,
            "peak_relative_db": f"{frame.peak_relative_db:.9f}",
        }
        with csv_temporary.open(
            "x", newline="", encoding="utf-8"
        ) as handle:
            writer = csv.DictWriter(handle, fieldnames=tuple(fields))
            writer.writeheader()
            writer.writerow(fields)
            _flush_and_sync(handle)

        os.replace(npz_temporary, paths.npz)
        os.replace(csv_temporary, paths.csv)
        return paths
    finally:
        npz_temporary.unlink(missing_ok=True)
        csv_temporary.unlink(missing_ok=True)
