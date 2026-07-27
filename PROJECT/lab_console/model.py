"""Immutable spectrum frames and plotting transforms for the lab console."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass

import numpy as np

from .protocol import FFT_SIZE, SpectrumResponse


RELATIVE_DB_FLOOR = -300.0


def _validate_fft_size(fft_size: int) -> int:
    if isinstance(fft_size, bool) or not isinstance(fft_size, int):
        raise ValueError("fft_size must be an integer")
    if fft_size <= 0 or fft_size % 2:
        raise ValueError("fft_size must be a positive even integer")
    return fft_size


def centered_natural_indices(fft_size: int) -> np.ndarray:
    """Return natural FFT bin indices in negative-to-positive order."""

    size = _validate_fft_size(fft_size)
    return np.concatenate(
        (
            np.arange(size // 2, size, dtype=np.int64),
            np.arange(0, size // 2, dtype=np.int64),
        )
    )


def centered_frequency_axis(
    lo_hz: int, sample_rate_hz: int, fft_size: int
) -> np.ndarray:
    """Return the centered RF frequency of each displayed FFT bin."""

    size = _validate_fft_size(fft_size)
    if sample_rate_hz <= 0:
        raise ValueError("sample_rate_hz must be positive")
    offsets = (
        np.arange(-size // 2, size // 2, dtype=np.float64)
        * (float(sample_rate_hz) / size)
    )
    axis = offsets + float(lo_hz)
    if sample_rate_hz % size == 0:
        axis = axis.astype(np.int64)
    axis.setflags(write=False)
    return axis


def relative_db(power: np.ndarray) -> np.ndarray:
    """Return finite peak-normalized power dB with a -300 dB floor."""

    values = np.asarray(power)
    if np.iscomplexobj(values) or not np.issubdtype(values.dtype, np.number):
        raise ValueError("power must contain real numeric values")
    numeric = values.astype(np.float64, copy=False)
    if numeric.ndim != 1 or not np.all(np.isfinite(numeric)):
        raise ValueError("power must be one-dimensional and finite")
    if np.any(numeric < 0):
        raise ValueError("power must be non-negative")
    maximum = float(np.max(numeric)) if numeric.size else 0.0
    if maximum <= 0.0:
        return np.full(numeric.shape, RELATIVE_DB_FLOOR, dtype=np.float64)
    result = np.full(numeric.shape, RELATIVE_DB_FLOOR, dtype=np.float64)
    positive = numeric > 0.0
    result[positive] = 10.0 * np.log10(numeric[positive] / maximum)
    np.maximum(result, RELATIVE_DB_FLOOR, out=result)
    return result


@dataclass(frozen=True)
class PlotFrame:
    response: SpectrumResponse
    natural_spectrum: np.ndarray
    centered_spectrum: np.ndarray
    frequency_hz: np.ndarray
    spectrum_db: np.ndarray
    peak_frequency_hz: float
    peak_relative_db: float


class SpectrumHistory:
    """Validate and retain up to 32 immutable plot frames."""

    def __init__(
        self,
        *,
        history: int = 32,
        search_start: int = 0,
        search_stop: int = FFT_SIZE - 1,
    ) -> None:
        if isinstance(history, bool) or not isinstance(history, int):
            raise ValueError("history must be an integer")
        if history < 1 or history > 32:
            raise ValueError("history must be within [1, 32]")
        if not 0 <= search_start <= search_stop < FFT_SIZE:
            raise ValueError("search range must be within the FFT")
        self._frames: deque[PlotFrame] = deque(maxlen=history)
        self._search_start = search_start
        self._search_stop = search_stop

    def __len__(self) -> int:
        return len(self._frames)

    @property
    def frames(self) -> tuple[PlotFrame, ...]:
        return tuple(self._frames)

    @property
    def waterfall_db(self) -> np.ndarray:
        if not self._frames:
            return np.empty((0, FFT_SIZE), dtype=np.float64)
        return np.stack(
            [frame.spectrum_db for frame in self._frames],
            axis=0,
        )

    def append(self, response: SpectrumResponse) -> PlotFrame:
        if response.fft_size != FFT_SIZE or response.sample_count != FFT_SIZE:
            raise ValueError("response is not an exact 2048-bin frame")
        if response.has_fatal_hardware_fault:
            raise ValueError("response contains fatal hardware flags")

        natural = np.array(response.spectrum, dtype=np.uint64, copy=True)
        if natural.shape != (FFT_SIZE,):
            raise ValueError("response spectrum must contain 2048 bins")
        search = natural[self._search_start : self._search_stop + 1]
        expected_peak = self._search_start + int(np.argmax(search))
        if response.peak_bin != expected_peak:
            raise ValueError(
                f"reported peak_bin {response.peak_bin} != {expected_peak}"
            )
        if response.peak_power != int(natural[expected_peak]):
            raise ValueError("reported peak_power does not match spectrum")

        order = centered_natural_indices(FFT_SIZE)
        centered = natural[order].copy()
        frequencies = centered_frequency_axis(
            response.lo_hz,
            response.sample_rate_hz,
            response.fft_size,
        )
        db = relative_db(centered)
        centered_peak = (response.peak_bin + FFT_SIZE // 2) % FFT_SIZE

        natural.setflags(write=False)
        centered.setflags(write=False)
        db.setflags(write=False)
        frame = PlotFrame(
            response=response,
            natural_spectrum=natural,
            centered_spectrum=centered,
            frequency_hz=frequencies,
            spectrum_db=db,
            peak_frequency_hz=float(frequencies[centered_peak]),
            peak_relative_db=float(db[centered_peak]),
        )
        self._frames.append(frame)
        return frame
