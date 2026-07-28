"""Strict controlled-CW evidence validation for the live FFT Candidate."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np


FFT_SIZE = 2048
MINIMUM_FRAMES = 10
RELEASE_ID = "monopulse-live-lab-v2"
_REQUIRED_METADATA = (
    "Candidate release",
    "Application SHA-256",
    "Bitstream SHA-256",
    "SMW200A frequency Hz",
    "SMW200A level dBm",
    "External attenuation dB",
    "RF path",
    "AD9364 LO Hz",
    "AD9364 sample rate Hz",
    "AD9364 bandwidth Hz",
    "AD9364 gain mode",
    "AD9364 gain dB",
    "Expected peak bin",
    "Peak tolerance bins",
    "NPZ SHA-256",
    "CSV SHA-256",
)
_IDENTITY_FIELDS = (
    "frame_id",
    "fft_size",
    "frame_crc32",
    "protocol_crc_valid",
    "peak_bin",
    "hardware_flags",
    "lo_hz",
    "sample_rate_hz",
    "rx_bandwidth_hz",
    "gain_mode",
    "gain_db",
    "release_id",
)


@dataclass(frozen=True)
class EvidenceResult:
    frame_count: int
    expected_peak_bin: int
    peak_min: int
    peak_max: int
    npz_sha256: str
    csv_sha256: str


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def _require_file(path: Path) -> Path:
    resolved = Path(path)
    if not resolved.is_file():
        raise FileNotFoundError(f"missing physical evidence: {resolved}")
    return resolved


def _parse_metadata(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key in fields:
            raise ValueError(f"duplicate evidence metadata field: {key}")
        fields[key] = value
    missing = [key for key in _REQUIRED_METADATA if not fields.get(key)]
    if missing:
        raise ValueError(
            "missing evidence metadata fields: " + ", ".join(missing)
        )
    return fields


def _parse_int(value: str, field: str, *, base: int = 10) -> int:
    try:
        return int(value, base)
    except ValueError as exc:
        raise ValueError(f"invalid integer for {field}: {value}") from exc


def _parse_float(value: str, field: str) -> float:
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValueError(f"invalid number for {field}: {value}") from exc
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite number for {field}")
    return parsed


def _manifest_artifacts(manifest_path: Path) -> tuple[dict, dict[str, dict]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    artifacts: dict[str, dict] = {}
    for artifact in manifest.get("artifacts", ()):
        name = artifact.get("name")
        if not isinstance(name, str) or name in artifacts:
            raise ValueError("Candidate manifest has duplicate artifact names")
        artifacts[name] = artifact
    for required in ("application", "bitstream"):
        if required not in artifacts:
            raise ValueError(
                f"Candidate manifest is missing {required} artifact"
            )
    return manifest, artifacts


def _verify_candidate(
    manifest_path: Path, metadata: dict[str, str]
) -> None:
    manifest, artifacts = _manifest_artifacts(manifest_path)
    if manifest.get("release_id") != RELEASE_ID:
        raise ValueError("unexpected Candidate release in manifest")
    if metadata["Candidate release"] != RELEASE_ID:
        raise ValueError("evidence Candidate release does not match")

    root = manifest_path.parent
    checks = (
        ("application", "Application SHA-256"),
        ("bitstream", "Bitstream SHA-256"),
    )
    for artifact_name, metadata_name in checks:
        artifact = artifacts[artifact_name]
        expected = str(artifact.get("sha256", "")).upper()
        recorded = metadata[metadata_name].upper()
        if recorded != expected:
            raise ValueError(
                f"{artifact_name} evidence hash does not match manifest"
            )
        artifact_path = _require_file(root / str(artifact.get("path", "")))
        if _sha256(artifact_path) != expected:
            raise ValueError(
                f"{artifact_name} file hash does not match manifest"
            )


def _required_array(
    saved: np.lib.npyio.NpzFile,
    name: str,
    frame_count: int,
) -> np.ndarray:
    if name not in saved.files:
        raise ValueError(f"NPZ is missing {name}")
    value = saved[name]
    if value.shape != (frame_count,):
        raise ValueError(f"NPZ {name} must contain one value per frame")
    return value


def _csv_integer(row: dict[str, str], field: str) -> int:
    base = 16 if field in ("frame_crc32", "hardware_flags") else 10
    return _parse_int(row.get(field, ""), f"CSV {field}", base=base)


def _verify_csv_identity(
    csv_path: Path,
    arrays: dict[str, np.ndarray],
    frame_count: int,
) -> None:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != frame_count:
        raise ValueError("CSV and NPZ frame counts do not match")
    for field in _IDENTITY_FIELDS:
        if field not in (rows[0] if rows else {}):
            raise ValueError(f"CSV is missing {field}")
    for index, row in enumerate(rows):
        for field in _IDENTITY_FIELDS:
            if field == "release_id":
                csv_value: object = row[field]
                npz_value: object = str(arrays[field][index])
            else:
                csv_value = _csv_integer(row, field)
                npz_value = int(arrays[field][index])
            if csv_value != npz_value:
                raise ValueError(
                    f"CSV/NPZ frame identity mismatch at row "
                    f"{index + 1}: {field}"
                )


def validate_cw_evidence(
    manifest_path: Path,
    evidence_path: Path,
    npz_path: Path,
    csv_path: Path,
) -> EvidenceResult:
    """Validate a controlled-CW capture and its immutable bindings."""

    manifest = _require_file(Path(manifest_path))
    evidence = _require_file(Path(evidence_path))
    capture = _require_file(Path(npz_path))
    summary = _require_file(Path(csv_path))
    metadata = _parse_metadata(evidence)
    _verify_candidate(manifest, metadata)

    npz_hash = _sha256(capture)
    csv_hash = _sha256(summary)
    if metadata["NPZ SHA-256"].upper() != npz_hash:
        raise ValueError("NPZ hash does not match evidence metadata")
    if metadata["CSV SHA-256"].upper() != csv_hash:
        raise ValueError("CSV hash does not match evidence metadata")

    source_hz = _parse_int(
        metadata["SMW200A frequency Hz"], "SMW200A frequency Hz"
    )
    _parse_float(metadata["SMW200A level dBm"], "SMW200A level dBm")
    attenuation = _parse_float(
        metadata["External attenuation dB"], "External attenuation dB"
    )
    if attenuation < 0:
        raise ValueError("external attenuation must not be negative")
    if len(metadata["RF path"]) < 4:
        raise ValueError("RF path description is incomplete")
    lo_hz = _parse_int(metadata["AD9364 LO Hz"], "AD9364 LO Hz")
    sample_rate_hz = _parse_int(
        metadata["AD9364 sample rate Hz"], "AD9364 sample rate Hz"
    )
    bandwidth_hz = _parse_int(
        metadata["AD9364 bandwidth Hz"], "AD9364 bandwidth Hz"
    )
    gain_mode = metadata["AD9364 gain mode"].strip().lower()
    gain_db = _parse_int(metadata["AD9364 gain dB"], "AD9364 gain dB")
    if gain_mode != "manual":
        raise ValueError("AD9364 gain mode must be manual")
    expected_peak = _parse_int(
        metadata["Expected peak bin"], "Expected peak bin"
    )
    tolerance = _parse_int(
        metadata["Peak tolerance bins"], "Peak tolerance bins"
    )
    if sample_rate_hz <= 0 or bandwidth_hz <= 0:
        raise ValueError("AD9364 sample rate and bandwidth must be positive")
    if not 0 <= expected_peak < FFT_SIZE:
        raise ValueError("expected peak bin is outside the FFT")
    if tolerance != 1:
        raise ValueError("controlled-CW peak tolerance must be exactly 1 bin")
    calculated_peak = round(
        ((source_hz - lo_hz) % sample_rate_hz)
        * FFT_SIZE
        / sample_rate_hz
    ) % FFT_SIZE
    if calculated_peak != expected_peak:
        raise ValueError(
            "SMW200A frequency does not map to expected peak bin"
        )
    if expected_peak == 0:
        raise ValueError("controlled CW must use a non-DC FFT offset")

    with np.load(capture, allow_pickle=False) as saved:
        if "spectrum" not in saved.files:
            raise ValueError("NPZ is missing spectrum")
        spectrum = saved["spectrum"]
        if (
            spectrum.ndim != 2
            or spectrum.shape[1] != FFT_SIZE
            or spectrum.dtype != np.uint64
        ):
            raise ValueError("NPZ spectrum must be Nx2048 uint64")
        frame_count = spectrum.shape[0]
        if frame_count < MINIMUM_FRAMES:
            raise ValueError("controlled-CW evidence needs at least 10 frames")
        arrays = {
            field: _required_array(saved, field, frame_count)
            for field in _IDENTITY_FIELDS
        }
        arrays["spectrum"] = spectrum

    frame_ids = arrays["frame_id"].astype(np.uint64)
    expected_ids = (
        frame_ids[0] + np.arange(frame_count, dtype=np.uint64)
    ) & np.uint64(0xFFFFFFFF)
    if not np.array_equal(frame_ids, expected_ids):
        raise ValueError("frame IDs are not consecutive")
    if np.any(arrays["fft_size"] != FFT_SIZE):
        raise ValueError("each captured frame must contain exact 2048 bins")
    if np.any(arrays["protocol_crc_valid"] != 1):
        raise ValueError("each captured frame must have a valid protocol CRC")
    if np.any(arrays["hardware_flags"] != 0):
        raise ValueError("fatal hardware flags must be zero")
    if np.any(arrays["release_id"] != RELEASE_ID):
        raise ValueError("NPZ contains an unexpected release ID")
    runtime_checks = (
        ("lo_hz", lo_hz),
        ("sample_rate_hz", sample_rate_hz),
        ("rx_bandwidth_hz", bandwidth_hz),
        ("gain_mode", 0),
        ("gain_db", gain_db),
    )
    for field, expected in runtime_checks:
        if np.any(arrays[field] != expected):
            raise ValueError(f"NPZ {field} does not match evidence metadata")

    peak_bins = arrays["peak_bin"].astype(np.int64)
    if np.any(np.abs(peak_bins - expected_peak) > tolerance):
        raise ValueError("peak bin is outside the required +/-1 stability")
    calculated_bins = np.argmax(arrays["spectrum"], axis=1)
    if not np.array_equal(calculated_bins, peak_bins):
        raise ValueError("stored peak bin does not match spectrum maximum")
    _verify_csv_identity(summary, arrays, frame_count)

    return EvidenceResult(
        frame_count=frame_count,
        expected_peak_bin=expected_peak,
        peak_min=int(peak_bins.min()),
        peak_max=int(peak_bins.max()),
        npz_sha256=npz_hash,
        csv_sha256=csv_hash,
    )


def _argument_parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parents[2]
    evidence_root = root / "PROJECT" / "tests" / "evidence"
    candidate = (
        root
        / "PROJECT"
        / "candidates"
        / "axu4ev-ad9364"
        / RELEASE_ID
    )
    parser = argparse.ArgumentParser(
        description="Validate AXU4EVB-P AD9364 controlled-CW evidence"
    )
    parser.add_argument(
        "--manifest", type=Path, default=candidate / "manifest.json"
    )
    parser.add_argument(
        "--evidence",
        type=Path,
        default=evidence_root / "axu4ev-ad9364-live-lab-cw-pass.md",
    )
    parser.add_argument(
        "--npz",
        type=Path,
        default=evidence_root
        / "axu4ev-ad9364-live-lab-cw-capture.npz",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=evidence_root / "axu4ev-ad9364-live-lab-cw-summary.csv",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    try:
        result = validate_cw_evidence(
            args.manifest, args.evidence, args.npz, args.csv
        )
    except (
        FileNotFoundError,
        OSError,
        ValueError,
        json.JSONDecodeError,
    ) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        "PASS: controlled-CW evidence "
        f"frames={result.frame_count} "
        f"expected_peak={result.expected_peak_bin} "
        f"observed={result.peak_min}..{result.peak_max}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
