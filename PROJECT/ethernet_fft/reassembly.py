"""Bounded reassembly of FFT UDP chunks into console spectrum responses."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from PROJECT.ethernet_fft.protocol import UdpFftChunk, UdpProtocolError
from PROJECT.lab_console.protocol import SpectrumResponse


_MAX_PENDING_FRAMES = 8


@dataclass
class PendingFrame:
    """Chunks and shared telemetry belonging to one incomplete FFT frame."""

    first_received_at: float
    frame_id: int
    chunk_count: int
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
    chunks: dict[int, UdpFftChunk] = field(default_factory=dict)
    highest_chunk_index: int = -1

    @classmethod
    def from_chunk(cls, chunk: UdpFftChunk, received_at: float) -> "PendingFrame":
        return cls(
            first_received_at=received_at,
            frame_id=chunk.frame_id,
            chunk_count=chunk.chunk_count,
            fft_size=chunk.fft_size,
            flags=chunk.flags,
            lo_hz=chunk.lo_hz,
            sample_rate_hz=chunk.sample_rate_hz,
            bandwidth_hz=chunk.bandwidth_hz,
            gain_db=chunk.gain_db,
            peak_bin=chunk.peak_bin,
            peak_power=chunk.peak_power,
            frame_crc32=chunk.frame_crc32,
            peak_re=chunk.peak_re,
            peak_im=chunk.peak_im,
            reset_epoch=chunk.reset_epoch,
            rf_state=chunk.rf_state,
            active_bank=chunk.active_bank,
        )

    def metadata_matches(self, chunk: UdpFftChunk) -> bool:
        """Return whether *chunk* carries the frame's shared metadata."""

        return (
            chunk.frame_id == self.frame_id
            and chunk.chunk_count == self.chunk_count
            and chunk.fft_size == self.fft_size
            and chunk.flags == self.flags
            and chunk.lo_hz == self.lo_hz
            and chunk.sample_rate_hz == self.sample_rate_hz
            and chunk.bandwidth_hz == self.bandwidth_hz
            and chunk.gain_db == self.gain_db
            and chunk.peak_bin == self.peak_bin
            and chunk.peak_power == self.peak_power
            and chunk.frame_crc32 == self.frame_crc32
            and chunk.peak_re == self.peak_re
            and chunk.peak_im == self.peak_im
            and chunk.reset_epoch == self.reset_epoch
            and chunk.rf_state == self.rf_state
            and chunk.active_bank == self.active_bank
        )

    @property
    def complete(self) -> bool:
        return len(self.chunks) == self.chunk_count

    def add(self, chunk: UdpFftChunk) -> None:
        self.chunks[chunk.chunk_index] = chunk
        self.highest_chunk_index = max(self.highest_chunk_index, chunk.chunk_index)

    def to_spectrum_response(self) -> SpectrumResponse:
        spectrum = np.empty(self.fft_size, dtype=np.uint64)
        for chunk in self.chunks.values():
            spectrum[chunk.first_bin : chunk.first_bin + chunk.bin_count] = chunk.bins

        return SpectrumResponse(
            sequence=self.frame_id,
            frame_id=self.frame_id,
            sample_count=self.fft_size,
            fft_size=self.fft_size,
            sample_rate_hz=self.sample_rate_hz,
            rx_bandwidth_hz=self.bandwidth_hz,
            lo_hz=self.lo_hz,
            frame_crc32=self.frame_crc32,
            skipped_sample_count=0,
            peak_power=self.peak_power,
            peak_bin=self.peak_bin,
            peak_re=self.peak_re,
            peak_im=self.peak_im,
            reset_epoch=self.reset_epoch,
            rf_state=self.rf_state,
            active_bank=self.active_bank,
            hardware_flags=self.flags,
            gain_db=self.gain_db,
            gain_mode=0,
            spectrum=spectrum,
        )


class FrameReassembler:
    """Reassemble up to eight concurrent FFT frames received over UDP."""

    def __init__(self, timeout_s: float) -> None:
        self.timeout_s = timeout_s
        self._frames: dict[int, PendingFrame] = {}
        self.completed_frames = 0
        self.lost_frames = 0
        self.duplicate_chunks = 0
        self.invalid_datagrams = 0
        self.out_of_order_chunks = 0

    def push(self, datagram: bytes, received_at: float) -> SpectrumResponse | None:
        """Accept one UDP datagram and return its response when complete."""

        try:
            chunk = UdpFftChunk.decode(datagram)
        except UdpProtocolError:
            self.invalid_datagrams += 1
            return None

        pending = self._frames.get(chunk.frame_id)
        if pending is None:
            self._evict_oldest_if_full()
            pending = PendingFrame.from_chunk(chunk, received_at)
            self._frames[chunk.frame_id] = pending
        elif not pending.metadata_matches(chunk):
            self.invalid_datagrams += 1
            del self._frames[chunk.frame_id]
            return None

        if chunk.chunk_index in pending.chunks:
            self.duplicate_chunks += 1
            return None
        if chunk.chunk_index < pending.highest_chunk_index:
            self.out_of_order_chunks += 1
        pending.add(chunk)
        if not pending.complete:
            return None

        del self._frames[chunk.frame_id]
        self.completed_frames += 1
        return pending.to_spectrum_response()

    def expire(self, now: float) -> int:
        """Discard incomplete frames whose first packet exceeded the timeout."""

        expired = [
            frame_id
            for frame_id, pending in self._frames.items()
            if now - pending.first_received_at > self.timeout_s
        ]
        for frame_id in expired:
            del self._frames[frame_id]
        self.lost_frames += len(expired)
        return len(expired)

    def _evict_oldest_if_full(self) -> None:
        if len(self._frames) < _MAX_PENDING_FRAMES:
            return
        oldest_frame_id = min(
            self._frames,
            key=lambda frame_id: self._frames[frame_id].first_received_at,
        )
        del self._frames[oldest_frame_id]
        self.lost_frames += 1
