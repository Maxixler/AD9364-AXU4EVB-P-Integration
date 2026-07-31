"""Strict decoder for the AXU4EV AD9364 FFT UDP wire protocol."""

from dataclasses import dataclass
import struct

import numpy as np


HEADER = struct.Struct("!IBBHIHHHHHHQIIhHQIhhHBB")

_MAGIC = 0x41464654
_VERSION = 1
_PACKET_TYPE_FFT = 1
_HEADER_BYTES = 64
_FFT_SIZE = 2048
_BINS_PER_CHUNK = 176
_CHUNK_COUNT = 12


class UdpProtocolError(ValueError):
    """Raised when a UDP datagram violates the FFT wire contract."""


@dataclass(frozen=True)
class UdpFftChunk:
    frame_id: int
    chunk_index: int
    chunk_count: int
    first_bin: int
    bin_count: int
    fft_size: int
    flags: int
    lo_hz: int
    sample_rate_hz: int
    bandwidth_hz: int
    gain_db: int
    peak_bin: int
    peak_power: int
    frame_crc32: int
    peak_re: int
    peak_im: int
    reset_epoch: int
    rf_state: int
    active_bank: int
    bins: np.ndarray

    @classmethod
    def decode(cls, datagram: bytes) -> "UdpFftChunk":
        if not isinstance(datagram, bytes):
            raise UdpProtocolError("datagram must be bytes")
        if len(datagram) < HEADER.size:
            raise UdpProtocolError("datagram shorter than 64-byte header")

        fields = HEADER.unpack_from(datagram)
        cls._validate_header(fields)
        payload = datagram[HEADER.size:]
        bin_count = fields[8]
        if len(payload) != bin_count * np.dtype("<u8").itemsize:
            raise UdpProtocolError("bin_count does not match payload length")

        return cls.from_fields(fields, np.frombuffer(payload, dtype="<u8").copy())

    @classmethod
    def from_fields(cls, fields: tuple[int, ...], bins: np.ndarray) -> "UdpFftChunk":
        return cls(
            frame_id=fields[4],
            chunk_index=fields[5],
            chunk_count=fields[6],
            first_bin=fields[7],
            bin_count=fields[8],
            fft_size=fields[9],
            flags=fields[10],
            lo_hz=fields[11],
            sample_rate_hz=fields[12],
            bandwidth_hz=fields[13],
            gain_db=fields[14],
            peak_bin=fields[15],
            peak_power=fields[16],
            frame_crc32=fields[17],
            peak_re=fields[18],
            peak_im=fields[19],
            reset_epoch=fields[20],
            rf_state=fields[21],
            active_bank=fields[22],
            bins=bins,
        )

    @staticmethod
    def _validate_header(fields: tuple[int, ...]) -> None:
        if fields[0] != _MAGIC or fields[1:4] != (_VERSION, _PACKET_TYPE_FFT, _HEADER_BYTES):
            raise UdpProtocolError("unsupported FFT UDP header")
        if fields[6] != _CHUNK_COUNT:
            raise UdpProtocolError("unsupported FFT UDP chunk_count")
        if fields[9] != _FFT_SIZE:
            raise UdpProtocolError("unsupported FFT UDP fft_size")

        chunk_index, first_bin, bin_count = fields[5], fields[7], fields[8]
        if chunk_index >= _CHUNK_COUNT:
            raise UdpProtocolError("chunk_index outside canonical range")
        expected_first_bin = chunk_index * _BINS_PER_CHUNK
        expected_bin_count = min(_BINS_PER_CHUNK, _FFT_SIZE - expected_first_bin)
        if first_bin != expected_first_bin or bin_count != expected_bin_count:
            raise UdpProtocolError("non-canonical FFT UDP chunk bounds")
        if first_bin + bin_count > _FFT_SIZE:
            raise UdpProtocolError("chunk bounds exceed fft_size")
