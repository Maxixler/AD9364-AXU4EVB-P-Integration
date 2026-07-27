"""pyadi-iio capture adapter for an AD936X IIO endpoint."""

from __future__ import annotations

from numbers import Integral

import numpy as np


_IIO_ERROR = "pyadi-iio requires a reachable Linux/IIOD IIO context"


def capture_ad936x(uri: str, sample_rate: int, bandwidth: int, lo_hz: int,
                   gain_db: float, samples: int) -> np.ndarray:
    """Configure RX channel zero and capture one complex vector from AD936X."""
    if isinstance(samples, bool) or not isinstance(samples, Integral) or samples <= 0:
        raise ValueError("samples must be a positive integer")
    try:
        import adi
    except ImportError as exc:
        raise RuntimeError(_IIO_ERROR) from exc

    try:
        sdr = adi.ad9361(uri=uri)
        sdr.rx_enabled_channels = [0]
        sdr.sample_rate = sample_rate
        sdr.rx_rf_bandwidth = bandwidth
        sdr.rx_lo = lo_hz
        sdr.gain_control_mode_chan0 = "manual"
        sdr.rx_hardwaregain_chan0 = gain_db
        sdr.rx_buffer_size = samples
        captured = np.asarray(sdr.rx())
        if captured.shape != (samples,) or not np.iscomplexobj(captured):
            raise ValueError("IIO capture did not return one complex RX vector")
        return captured
    except Exception as exc:
        raise RuntimeError(_IIO_ERROR) from exc
