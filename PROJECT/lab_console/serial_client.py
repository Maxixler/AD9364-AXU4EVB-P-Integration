"""Request-driven serial transport for the bare-metal FFT lab protocol."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Callable

from .protocol import (
    ERROR,
    INFO,
    SPECTRUM,
    ErrorResponse,
    InfoResponse,
    MessageDecoder,
    ProtocolError,
    SpectrumResponse,
    decode_error,
    decode_info,
    decode_spectrum,
    encode_capture_once,
    encode_get_info,
)


class TransportError(RuntimeError):
    """The serial request could not produce a valid response."""


class TransportTimeout(TransportError):
    """No valid response arrived before the request deadline."""


class BoardError(RuntimeError):
    """The target returned a protocol ERROR response."""

    def __init__(self, error: ErrorResponse) -> None:
        self.error = error
        super().__init__(
            f"board error code={error.error_code} stage={error.stage}"
        )


@dataclass(frozen=True)
class CaptureConfig:
    search_start: int = 0
    search_stop: int = 2047
    dc_guard: int = 0
    rf_state: int = 0

    def __post_init__(self) -> None:
        if not 0 <= self.search_start <= self.search_stop < 2048:
            raise ValueError("search range must be within [0, 2047]")
        if not 0 <= self.dc_guard <= 1024:
            raise ValueError("dc_guard must be within [0, 1024]")
        if not 0 <= self.rf_state <= 7:
            raise ValueError("rf_state must be within [0, 7]")


def _open_pyserial(**kwargs: Any) -> Any:
    try:
        import serial
    except ImportError as exc:
        raise RuntimeError(
            "pyserial is required for a physical COM port"
        ) from exc
    return serial.Serial(**kwargs)


class LabSerialClient:
    """Send one command at a time and accept only its validated response."""

    def __init__(
        self,
        port: str,
        *,
        baud: int = 115200,
        timeout: float = 5.0,
        retries: int = 1,
        serial_factory: Callable[..., Any] | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if not port:
            raise ValueError("port is required")
        if baud <= 0 or timeout <= 0:
            raise ValueError("baud and timeout must be positive")
        if retries < 0:
            raise ValueError("retries must be non-negative")
        self.port = port
        self.baud = baud
        self.timeout = float(timeout)
        self.retries = retries
        self._serial_factory = serial_factory or _open_pyserial
        self._clock = clock
        self._serial: Any | None = None
        self._sequence = 0

    def __enter__(self) -> "LabSerialClient":
        if self._serial is not None:
            raise RuntimeError("serial client is already open")
        self._serial = self._serial_factory(
            port=self.port,
            baudrate=self.baud,
            timeout=min(self.timeout, 0.1),
        )
        return self

    def __exit__(self, *_: object) -> None:
        serial_port = self._serial
        self._serial = None
        if serial_port is not None:
            serial_port.close()

    def get_info(self) -> InfoResponse:
        sequence = self._next_sequence()
        envelope = self._request(
            encode_get_info(sequence),
            sequence,
            INFO,
        )
        return decode_info(envelope)

    def capture_once(self, config: CaptureConfig) -> SpectrumResponse:
        sequence = self._next_sequence()
        envelope = self._request(
            encode_capture_once(
                sequence,
                config.search_start,
                config.search_stop,
                config.dc_guard,
                config.rf_state,
            ),
            sequence,
            SPECTRUM,
        )
        return decode_spectrum(envelope)

    def _next_sequence(self) -> int:
        self._sequence = (self._sequence + 1) & 0xFFFFFFFF
        if self._sequence == 0:
            self._sequence = 1
        return self._sequence

    def _request(
        self,
        request: bytes,
        sequence: int,
        expected_type: int,
    ) -> Any:
        serial_port = self._serial
        if serial_port is None:
            raise RuntimeError("serial client must be used as a context manager")

        for _attempt in range(self.retries + 1):
            if serial_port.write(request) != len(request):
                continue
            decoder = MessageDecoder()
            deadline = self._clock() + self.timeout
            retry_for_crc = False
            while self._clock() < deadline:
                chunk = serial_port.read(4096)
                if not chunk:
                    continue
                crc_errors = decoder.crc_error_count
                envelopes = decoder.feed(chunk)
                if decoder.crc_error_count != crc_errors:
                    retry_for_crc = True
                    break
                for envelope in envelopes:
                    if envelope.sequence != sequence:
                        continue
                    if envelope.message_type == ERROR:
                        raise BoardError(decode_error(envelope))
                    if envelope.message_type != expected_type:
                        raise ProtocolError(
                            "response type does not match request"
                        )
                    return envelope
            if retry_for_crc:
                continue
        raise TransportTimeout(
            f"no valid response within {self.timeout:.1f} seconds"
        )
