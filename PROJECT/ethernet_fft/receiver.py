"""Continuous UDP transport for reassembled AXU4EV FFT frames."""

from __future__ import annotations

from dataclasses import dataclass
import socket
import time
from typing import Callable, Iterable, Iterator, Protocol

from PROJECT.ethernet_fft.reassembly import FrameReassembler
from PROJECT.lab_console.protocol import SpectrumResponse


_RECEIVE_BYTES = 2048
_RECEIVE_BUFFER_BYTES = 1024 * 1024
_SOCKET_TIMEOUT_S = 0.25
_REASSEMBLY_TIMEOUT_S = 1.0


class DatagramSource(Protocol):
    def recvfrom(self, size: int) -> tuple[bytes, object]: ...

    def close(self) -> None: ...


@dataclass(frozen=True)
class ReceiverStats:
    """Snapshot of transport and frame-reassembly counters."""

    packets_received: int
    completed_frames: int
    lost_frames: int
    invalid_datagrams: int
    duplicate_chunks: int
    out_of_order_chunks: int


class _IterableDatagramSource:
    def __init__(self, datagrams: Iterable[bytes]) -> None:
        self._datagrams = iter(datagrams)

    def recvfrom(self, size: int) -> tuple[bytes, object]:
        del size
        return next(self._datagrams), None

    def close(self) -> None:
        return None


class UdpFftReceiver:
    """Yield complete FFT responses from a bound UDP socket continuously."""

    def __init__(
        self,
        bind: str = "192.168.1.100",
        port: int = 5005,
        *,
        _source: DatagramSource | None = None,
        _clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if _source is None:
            udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                udp_socket.setsockopt(
                    socket.SOL_SOCKET,
                    socket.SO_RCVBUF,
                    _RECEIVE_BUFFER_BYTES,
                )
                udp_socket.settimeout(_SOCKET_TIMEOUT_S)
                udp_socket.bind((bind, port))
            except BaseException:
                udp_socket.close()
                raise
            self.socket: DatagramSource = udp_socket
        else:
            self.socket = _source
        self.reassembler = FrameReassembler(timeout_s=_REASSEMBLY_TIMEOUT_S)
        self._clock = _clock
        self._packets_received = 0

    @classmethod
    def from_datagrams(cls, datagrams: Iterable[bytes]) -> "UdpFftReceiver":
        """Build a receiver over deterministic datagrams for tests/tools."""

        return cls(_source=_IterableDatagramSource(datagrams))

    @property
    def stats(self) -> ReceiverStats:
        """Return a stable snapshot of all receiver counters."""

        return ReceiverStats(
            packets_received=self._packets_received,
            completed_frames=self.reassembler.completed_frames,
            lost_frames=self.reassembler.lost_frames,
            invalid_datagrams=self.reassembler.invalid_datagrams,
            duplicate_chunks=self.reassembler.duplicate_chunks,
            out_of_order_chunks=self.reassembler.out_of_order_chunks,
        )

    def frames(
        self,
        limit: int = 0,
        *,
        stop: Callable[[SpectrumResponse], bool] | None = None,
    ) -> Iterator[SpectrumResponse]:
        """Yield frames until a positive limit or optional stop predicate."""

        if isinstance(limit, bool) or not isinstance(limit, int) or limit < 0:
            raise ValueError("limit must be a non-negative integer")
        completed = 0
        while limit == 0 or completed < limit:
            try:
                datagram, _peer = self.socket.recvfrom(_RECEIVE_BYTES)
            except socket.timeout:
                self.reassembler.expire(self._clock())
                continue
            except (KeyboardInterrupt, StopIteration):
                return

            now = self._clock()
            self._packets_received += 1
            response = self.reassembler.push(datagram, now)
            self.reassembler.expire(now)
            if response is None:
                continue
            completed += 1
            yield response
            if stop is not None and stop(response):
                return

    def close(self) -> None:
        self.socket.close()

    def __enter__(self) -> "UdpFftReceiver":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()
