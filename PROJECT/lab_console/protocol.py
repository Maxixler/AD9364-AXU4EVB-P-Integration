"""Versioned binary protocol shared by the lab console and bare-metal target."""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass

import numpy as np


REQUEST_MAGIC = b"MPLQ"
RESPONSE_MAGIC = b"MPLR"
PROTOCOL_VERSION = 2

GET_INFO = 0x01
INFO = 0x02
CAPTURE_ONCE = 0x03
SPECTRUM = 0x04
ERROR = 0x7E

HEADER = struct.Struct("<4sBBHII")
CRC = struct.Struct("<I")
CAPTURE = struct.Struct("<HHHBB")
INFO_PREFIX = struct.Struct("<HHIIHBBIIQhBB32s")
SPECTRUM_PREFIX = struct.Struct("<IHHIIQIIQHhhHBBHhBB")
ERROR_PAYLOAD = struct.Struct("<iHH")

MAX_PAYLOAD = 16448
FFT_SIZE = 2048
SPECTRUM_WORD_BYTES = 8
_MAX_WIRE_SIZE = HEADER.size + MAX_PAYLOAD + CRC.size
_RESPONSE_TYPES = frozenset((INFO, SPECTRUM, ERROR))
_FEATURE_MASK = 0x0000000F
_HARDWARE_FLAG_NAMES = (
    "frame_error",
    "fft_error",
    "fft_overflow",
    "cdc_fault",
    "bank_overrun",
    "dropped_during_capture",
)
_HARDWARE_FLAG_MASK = (1 << len(_HARDWARE_FLAG_NAMES)) - 1


class ProtocolError(ValueError):
    """A decoded message violates the version-2 wire contract."""


@dataclass(frozen=True)
class Envelope:
    """A CRC-validated response envelope."""

    message_type: int
    flags: int
    sequence: int
    payload: bytes


@dataclass(frozen=True)
class InfoResponse:
    sequence: int
    board_code: int
    rf_device_code: int
    firmware_version: int
    feature_bits: int
    fft_size: int
    spectrum_word_bytes: int
    rf_state_count: int
    sample_rate_hz: int
    rx_bandwidth_hz: int
    lo_hz: int
    gain_db: int
    gain_mode: int
    release_id: str


@dataclass(frozen=True)
class SpectrumResponse:
    sequence: int
    frame_id: int
    sample_count: int
    fft_size: int
    sample_rate_hz: int
    rx_bandwidth_hz: int
    lo_hz: int
    frame_crc32: int
    skipped_sample_count: int
    peak_power: int
    peak_bin: int
    peak_re: int
    peak_im: int
    reset_epoch: int
    rf_state: int
    active_bank: int
    hardware_flags: int
    gain_db: int
    gain_mode: int
    spectrum: np.ndarray

    @property
    def hardware_faults(self) -> tuple[str, ...]:
        return tuple(
            name
            for bit, name in enumerate(_HARDWARE_FLAG_NAMES)
            if self.hardware_flags & (1 << bit)
        )

    @property
    def has_fatal_hardware_fault(self) -> bool:
        return bool(self.hardware_flags & _HARDWARE_FLAG_MASK)


@dataclass(frozen=True)
class ErrorResponse:
    sequence: int
    error_code: int
    stage: int
    detail: int


def _encode(
    magic: bytes,
    message_type: int,
    flags: int,
    sequence: int,
    payload: bytes,
) -> bytes:
    prefix = HEADER.pack(
        magic,
        PROTOCOL_VERSION,
        message_type,
        flags,
        len(payload),
        sequence,
    ) + payload
    return prefix + CRC.pack(zlib.crc32(prefix) & 0xFFFFFFFF)


def encode_get_info(sequence: int) -> bytes:
    """Encode a version-2 GET_INFO request."""

    return _encode(REQUEST_MAGIC, GET_INFO, 0, sequence, b"")


def encode_capture_once(
    sequence: int,
    search_start: int,
    search_stop: int,
    dc_guard: int,
    rf_state: int,
) -> bytes:
    """Encode a version-2 CAPTURE_ONCE request."""

    payload = CAPTURE.pack(
        search_start,
        search_stop,
        dc_guard,
        rf_state,
        0,
    )
    return _encode(REQUEST_MAGIC, CAPTURE_ONCE, 0, sequence, payload)


def decode_info(envelope: Envelope) -> InfoResponse:
    _require_envelope(envelope, INFO, INFO_PREFIX.size)
    (
        board_code,
        rf_device_code,
        firmware_version,
        feature_bits,
        fft_size,
        spectrum_word_bytes,
        rf_state_count,
        sample_rate_hz,
        rx_bandwidth_hz,
        lo_hz,
        gain_db,
        gain_mode,
        reserved,
        release_raw,
    ) = INFO_PREFIX.unpack(envelope.payload)
    if feature_bits & ~_FEATURE_MASK:
        raise ProtocolError("INFO feature bits contain reserved values")
    if fft_size != FFT_SIZE:
        raise ProtocolError(f"INFO fft_size must be {FFT_SIZE}")
    if spectrum_word_bytes != SPECTRUM_WORD_BYTES:
        raise ProtocolError(
            f"INFO spectrum_word_bytes must be {SPECTRUM_WORD_BYTES}"
        )
    if rf_state_count not in (1, 4):
        raise ProtocolError("INFO rf_state_count must be 1 or 4")
    if gain_mode != 0:
        raise ProtocolError("INFO gain_mode must be manual")
    if reserved != 0:
        raise ProtocolError("INFO reserved byte must be zero")
    release_id = _decode_padded_ascii(release_raw, "release_id")
    return InfoResponse(
        sequence=envelope.sequence,
        board_code=board_code,
        rf_device_code=rf_device_code,
        firmware_version=firmware_version,
        feature_bits=feature_bits,
        fft_size=fft_size,
        spectrum_word_bytes=spectrum_word_bytes,
        rf_state_count=rf_state_count,
        sample_rate_hz=sample_rate_hz,
        rx_bandwidth_hz=rx_bandwidth_hz,
        lo_hz=lo_hz,
        gain_db=gain_db,
        gain_mode=gain_mode,
        release_id=release_id,
    )


def decode_spectrum(envelope: Envelope) -> SpectrumResponse:
    expected_length = SPECTRUM_PREFIX.size + FFT_SIZE * SPECTRUM_WORD_BYTES
    _require_envelope(envelope, SPECTRUM, expected_length)
    (
        frame_id,
        sample_count,
        fft_size,
        sample_rate_hz,
        rx_bandwidth_hz,
        lo_hz,
        frame_crc32,
        skipped_sample_count,
        peak_power,
        peak_bin,
        peak_re,
        peak_im,
        reset_epoch,
        rf_state,
        active_bank,
        hardware_flags,
        gain_db,
        gain_mode,
        reserved,
    ) = SPECTRUM_PREFIX.unpack_from(envelope.payload)
    if sample_count != FFT_SIZE:
        raise ProtocolError(f"SPECTRUM sample_count must be {FFT_SIZE}")
    if fft_size != FFT_SIZE:
        raise ProtocolError(f"SPECTRUM fft_size must be {FFT_SIZE}")
    if peak_bin >= FFT_SIZE:
        raise ProtocolError("SPECTRUM peak_bin is outside the FFT")
    if rf_state > 7:
        raise ProtocolError("SPECTRUM rf_state is outside version-2 range")
    if active_bank > 1:
        raise ProtocolError("SPECTRUM active_bank must be 0 or 1")
    if hardware_flags & ~_HARDWARE_FLAG_MASK:
        raise ProtocolError("SPECTRUM hardware_flags contain reserved bits")
    if gain_mode != 0:
        raise ProtocolError("SPECTRUM gain_mode must be manual")
    if reserved != 0:
        raise ProtocolError("SPECTRUM reserved word must be zero")

    spectrum = np.frombuffer(
        envelope.payload,
        dtype="<u8",
        count=FFT_SIZE,
        offset=SPECTRUM_PREFIX.size,
    )
    return SpectrumResponse(
        sequence=envelope.sequence,
        frame_id=frame_id,
        sample_count=sample_count,
        fft_size=fft_size,
        sample_rate_hz=sample_rate_hz,
        rx_bandwidth_hz=rx_bandwidth_hz,
        lo_hz=lo_hz,
        frame_crc32=frame_crc32,
        skipped_sample_count=skipped_sample_count,
        peak_power=peak_power,
        peak_bin=peak_bin,
        peak_re=peak_re,
        peak_im=peak_im,
        reset_epoch=reset_epoch,
        rf_state=rf_state,
        active_bank=active_bank,
        hardware_flags=hardware_flags,
        gain_db=gain_db,
        gain_mode=gain_mode,
        spectrum=spectrum,
    )


def decode_error(envelope: Envelope) -> ErrorResponse:
    _require_envelope(envelope, ERROR, ERROR_PAYLOAD.size)
    error_code, stage, detail = ERROR_PAYLOAD.unpack(envelope.payload)
    if detail != 0:
        raise ProtocolError("ERROR detail must be zero in protocol v2")
    if stage not in range(1, 6):
        raise ProtocolError("ERROR stage is outside protocol v2")
    return ErrorResponse(
        sequence=envelope.sequence,
        error_code=error_code,
        stage=stage,
        detail=detail,
    )


def _require_envelope(
    envelope: Envelope, message_type: int, payload_length: int
) -> None:
    if envelope.message_type != message_type:
        raise ProtocolError(
            f"unexpected message type 0x{envelope.message_type:02x}"
        )
    if envelope.flags != 0:
        raise ProtocolError("protocol v2 response flags must be zero")
    if len(envelope.payload) != payload_length:
        raise ProtocolError(
            f"payload length {len(envelope.payload)} != {payload_length}"
        )


def _decode_padded_ascii(value: bytes, field_name: str) -> str:
    terminator = value.find(b"\0")
    if terminator < 0:
        terminator = len(value)
    elif any(value[terminator:]):
        raise ProtocolError(f"{field_name} has nonzero reserved padding")
    try:
        return value[:terminator].decode("ascii")
    except UnicodeDecodeError as exc:
        raise ProtocolError(f"{field_name} is not ASCII") from exc


class MessageDecoder:
    """Incrementally decode bounded, CRC-protected target responses."""

    def __init__(self) -> None:
        self._buffer = bytearray()
        self.crc_error_count = 0
        self.protocol_error_count = 0

    @property
    def buffered_bytes(self) -> int:
        return len(self._buffer)

    def feed(self, data: bytes) -> list[Envelope]:
        if data:
            self._buffer.extend(data)

        decoded: list[Envelope] = []
        while True:
            magic_at = self._buffer.find(RESPONSE_MAGIC)
            if magic_at < 0:
                self._retain_possible_magic_prefix()
                break
            if magic_at:
                del self._buffer[:magic_at]

            if len(self._buffer) < HEADER.size:
                break

            (
                magic,
                version,
                message_type,
                flags,
                payload_length,
                sequence,
            ) = HEADER.unpack_from(self._buffer)
            if magic != RESPONSE_MAGIC:
                del self._buffer[0]
                continue
            if payload_length > MAX_PAYLOAD:
                self.protocol_error_count += 1
                del self._buffer[0]
                continue

            wire_size = HEADER.size + payload_length + CRC.size
            if len(self._buffer) < wire_size:
                break

            prefix = bytes(self._buffer[: HEADER.size + payload_length])
            received_crc = CRC.unpack_from(
                self._buffer, HEADER.size + payload_length
            )[0]
            if (zlib.crc32(prefix) & 0xFFFFFFFF) != received_crc:
                self.crc_error_count += 1
                del self._buffer[0]
                continue

            if (
                version != PROTOCOL_VERSION
                or message_type not in _RESPONSE_TYPES
            ):
                self.protocol_error_count += 1
                del self._buffer[:wire_size]
                continue

            payload = bytes(self._buffer[HEADER.size : HEADER.size + payload_length])
            decoded.append(
                Envelope(
                    message_type=message_type,
                    flags=flags,
                    sequence=sequence,
                    payload=payload,
                )
            )
            del self._buffer[:wire_size]

        if len(self._buffer) > _MAX_WIRE_SIZE:
            del self._buffer[:-_MAX_WIRE_SIZE]
        return decoded

    def _retain_possible_magic_prefix(self) -> None:
        keep = 0
        max_prefix = min(len(self._buffer), len(RESPONSE_MAGIC) - 1)
        for length in range(1, max_prefix + 1):
            if self._buffer[-length:] == RESPONSE_MAGIC[:length]:
                keep = length
        if keep:
            del self._buffer[:-keep]
        else:
            self._buffer.clear()
