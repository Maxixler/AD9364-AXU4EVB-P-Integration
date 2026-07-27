"""Floating-point NumPy reference for the four-state monopulse DSP path."""

from __future__ import annotations

from numbers import Integral

import numpy as np


STATE_COUNT = 4
FFT_SIZE = 2048


def _require_index(value: int, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, Integral):
        raise ValueError(f"{name} must be an integer")
    return int(value)


def _validate_interval(interval: tuple[int, int], name: str) -> tuple[int, int]:
    if not isinstance(interval, tuple) or len(interval) != 2:
        raise ValueError(f"{name} must be a (start, stop) tuple")
    start = _require_index(interval[0], f"{name} start")
    stop = _require_index(interval[1], f"{name} stop")
    if start < 0 or stop < start or stop >= FFT_SIZE:
        raise ValueError(f"{name} must be an inclusive interval within [0, {FFT_SIZE - 1}]")
    return start, stop


def _validated_spectra(spectra: np.ndarray) -> np.ndarray:
    array = np.asarray(spectra)
    if array.shape != (STATE_COUNT, FFT_SIZE):
        raise ValueError(f"spectra must have shape ({STATE_COUNT}, {FFT_SIZE})")
    if np.iscomplexobj(array) or not np.issubdtype(array.dtype, np.number):
        raise ValueError("spectra must contain real power values")
    array = array.astype(np.float64, copy=False)
    if not np.all(np.isfinite(array)):
        raise ValueError("spectra must contain only finite values")
    if np.any(array < 0.0):
        raise ValueError("spectra must contain non-negative power values")
    return array


def spectra_from_frames(frames: np.ndarray, window: str = "rectangular") -> np.ndarray:
    """Return four real power spectra from four 2048-sample complex frames."""
    array = np.asarray(frames)
    if array.shape != (STATE_COUNT, FFT_SIZE):
        raise ValueError(f"frames must have shape ({STATE_COUNT}, {FFT_SIZE})")
    if not np.issubdtype(array.dtype, np.number) or not np.all(np.isfinite(array)):
        raise ValueError("frames must contain only finite numeric values")
    if window == "rectangular":
        weights = np.ones(FFT_SIZE, dtype=np.float64)
    elif window == "hann":
        weights = np.hanning(FFT_SIZE)
    else:
        raise ValueError("window must be 'rectangular' or 'hann'")
    transformed = np.fft.fft(array * weights, axis=1)
    return np.abs(transformed) ** 2


def find_common_peak(spectra: np.ndarray, search: tuple[int, int], dc_guard: int) -> tuple[int, float]:
    """Find the lower-bin-wins maximum of the four-state common spectrum."""
    array = _validated_spectra(spectra)
    start, stop = _validate_interval(search, "search")
    guard = _require_index(dc_guard, "dc_guard")
    if guard < 0 or guard >= FFT_SIZE:
        raise ValueError(f"dc_guard must be within [0, {FFT_SIZE - 1}]")
    first = max(start, guard)
    if first > stop:
        raise ValueError("dc_guard excludes the complete search interval")
    common_power = array[:, first : stop + 1].sum(axis=0)
    offset = int(np.argmax(common_power))
    return first + offset, float(common_power[offset])


def integrate_cw(spectra: np.ndarray, peak_bin: int, half_width: int = 2) -> np.ndarray:
    """Integrate each state over the inclusive CW interval about ``peak_bin``."""
    array = _validated_spectra(spectra)
    peak = _require_index(peak_bin, "peak_bin")
    width = _require_index(half_width, "half_width")
    if width < 0 or width >= FFT_SIZE or peak < width or peak + width >= FFT_SIZE:
        raise ValueError("peak_bin and half_width must form an in-range inclusive CW interval")
    return array[:, peak - width : peak + width + 1].sum(axis=1)


def integrate_band(spectra: np.ndarray, band: tuple[int, int]) -> np.ndarray:
    """Integrate each state over the inclusive configured band."""
    array = _validated_spectra(spectra)
    start, stop = _validate_interval(band, "band")
    return array[:, start : stop + 1].sum(axis=1)


def normalized_errors(powers: np.ndarray, denominator_threshold: float) -> tuple[float, float]:
    """Compute AZ and EL normalized errors in AZ+, AZ-, EL+, EL- order."""
    array = np.asarray(powers, dtype=np.float64)
    if array.shape != (STATE_COUNT,) or not np.all(np.isfinite(array)) or np.any(array < 0.0):
        raise ValueError("powers must be four finite non-negative values")
    threshold = float(denominator_threshold)
    if not np.isfinite(threshold) or threshold <= 0.0:
        raise ValueError("denominator_threshold must be finite and positive")
    az_denominator = array[0] + array[1]
    el_denominator = array[2] + array[3]
    if az_denominator < threshold or el_denominator < threshold:
        raise ValueError("monopulse denominator is below denominator_threshold")
    return (
        float((array[0] - array[1]) / az_denominator),
        float((array[2] - array[3]) / el_denominator),
    )
