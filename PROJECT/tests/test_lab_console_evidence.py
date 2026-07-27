import csv
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from PROJECT.lab_console.evidence import validate_cw_evidence


ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = (
    ROOT
    / "PROJECT"
    / "candidates"
    / "axu4ev-ad9364"
    / "monopulse-live-lab-v1"
)
MANIFEST = CANDIDATE / "manifest.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _write_valid_fixture(root: Path) -> tuple[Path, Path, Path]:
    frame_count = 10
    peak_bin = 123
    lo_hz = 2_400_000_000
    sample_rate_hz = 30_720_000
    bandwidth_hz = 10_000_000
    source_hz = lo_hz + peak_bin * (sample_rate_hz // 2048)
    frame_ids = np.arange(100, 100 + frame_count, dtype=np.uint32)
    peak_bins = np.array(
        [122, 123, 124, 123, 122, 124, 123, 123, 122, 124],
        dtype=np.uint16,
    )
    spectrum = np.ones((frame_count, 2048), dtype=np.uint64)
    for index, frame_peak in enumerate(peak_bins):
        spectrum[index, frame_peak] = 100_000 + index

    npz_path = root / "axu4ev-ad9364-live-lab-cw-capture.npz"
    csv_path = root / "axu4ev-ad9364-live-lab-cw-summary.csv"
    evidence_path = root / "axu4ev-ad9364-live-lab-cw-pass.md"
    np.savez(
        npz_path,
        spectrum=spectrum,
        frame_id=frame_ids,
        fft_size=np.full(frame_count, 2048, dtype=np.uint16),
        frame_crc32=np.arange(1, frame_count + 1, dtype=np.uint32),
        protocol_crc_valid=np.ones(frame_count, dtype=np.uint8),
        peak_bin=peak_bins,
        hardware_flags=np.zeros(frame_count, dtype=np.uint16),
        lo_hz=np.full(frame_count, lo_hz, dtype=np.uint64),
        sample_rate_hz=np.full(
            frame_count, sample_rate_hz, dtype=np.uint32
        ),
        rx_bandwidth_hz=np.full(
            frame_count, bandwidth_hz, dtype=np.uint32
        ),
        release_id=np.full(
            frame_count, "monopulse-live-lab-v1", dtype="<U32"
        ),
    )
    fieldnames = (
        "frame_id",
        "fft_size",
        "frame_crc32",
        "protocol_crc_valid",
        "peak_bin",
        "hardware_flags",
        "lo_hz",
        "sample_rate_hz",
        "rx_bandwidth_hz",
        "release_id",
    )
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for index in range(frame_count):
            writer.writerow(
                {
                    "frame_id": int(frame_ids[index]),
                    "fft_size": 2048,
                    "frame_crc32": f"{index + 1:08x}",
                    "protocol_crc_valid": 1,
                    "peak_bin": int(peak_bins[index]),
                    "hardware_flags": "0000",
                    "lo_hz": lo_hz,
                    "sample_rate_hz": sample_rate_hz,
                    "rx_bandwidth_hz": bandwidth_hz,
                    "release_id": "monopulse-live-lab-v1",
                }
            )

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    artifacts = {
        item["name"]: item["sha256"] for item in manifest["artifacts"]
    }
    evidence_path.write_text(
        "\n".join(
            (
                "# AXU4EVB-P + AD9364 controlled-CW acceptance",
                "",
                "Candidate release: monopulse-live-lab-v1",
                f"Application SHA-256: {artifacts['application']}",
                f"Bitstream SHA-256: {artifacts['bitstream']}",
                f"SMW200A frequency Hz: {source_hz}",
                "SMW200A level dBm: -60.0",
                "External attenuation dB: 20.0",
                "RF path: approved direct cable and attenuator",
                f"AD9364 LO Hz: {lo_hz}",
                f"AD9364 sample rate Hz: {sample_rate_hz}",
                f"AD9364 bandwidth Hz: {bandwidth_hz}",
                f"Expected peak bin: {peak_bin}",
                "Peak tolerance bins: 1",
                f"NPZ SHA-256: {_sha256(npz_path)}",
                f"CSV SHA-256: {_sha256(csv_path)}",
                "",
            )
        ),
        encoding="utf-8",
    )
    return evidence_path, npz_path, csv_path


class ControlledCwEvidenceTests(unittest.TestCase):
    def test_valid_ten_frame_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            evidence, npz_path, csv_path = _write_valid_fixture(
                Path(temporary)
            )
            result = validate_cw_evidence(
                MANIFEST, evidence, npz_path, csv_path
            )
        self.assertEqual(result.frame_count, 10)
        self.assertEqual(result.expected_peak_bin, 123)
        self.assertEqual(result.peak_min, 122)
        self.assertEqual(result.peak_max, 124)

    def test_missing_physical_evidence_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(FileNotFoundError):
                validate_cw_evidence(
                    MANIFEST,
                    root / "missing.md",
                    root / "missing.npz",
                    root / "missing.csv",
                )

    def test_peak_outside_plus_or_minus_one_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            evidence, npz_path, csv_path = _write_valid_fixture(
                Path(temporary)
            )
            with np.load(npz_path) as saved:
                values = {name: saved[name] for name in saved.files}
            values["peak_bin"] = values["peak_bin"].copy()
            values["peak_bin"][4] = 126
            np.savez(npz_path, **values)
            text = evidence.read_text(encoding="utf-8")
            text = text.replace(
                next(
                    line
                    for line in text.splitlines()
                    if line.startswith("NPZ SHA-256:")
                ),
                f"NPZ SHA-256: {_sha256(npz_path)}",
            )
            evidence.write_text(text, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "peak bin"):
                validate_cw_evidence(
                    MANIFEST, evidence, npz_path, csv_path
                )


if __name__ == "__main__":
    unittest.main()
