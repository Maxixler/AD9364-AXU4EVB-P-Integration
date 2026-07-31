import socket

from PROJECT.ethernet_fft.receiver import UdpFftReceiver
from PROJECT.tests.test_ethernet_fft_reassembly import make_frame


def test_zero_limit_is_continuous_past_one_hundred_frames() -> None:
    receiver = UdpFftReceiver.from_datagrams(
        datagram
        for frame_id in range(1, 151)
        for datagram in make_frame(frame_id)
    )

    observed = list(
        receiver.frames(limit=0, stop=lambda response: response.frame_id == 150)
    )

    assert len(observed) == 150
    assert observed[100].frame_id == 101
    assert observed[-1].frame_id == 150
    assert receiver.stats.packets_received == 150 * 12
    assert receiver.stats.completed_frames == 150


def test_positive_limit_stops_for_acceptance_capture() -> None:
    receiver = UdpFftReceiver.from_datagrams(
        datagram
        for frame_id in range(1, 151)
        for datagram in make_frame(frame_id)
    )

    observed = list(receiver.frames(limit=100))

    assert len(observed) == 100
    assert observed[-1].frame_id == 100


def test_bound_socket_uses_large_receive_buffer_and_short_timeout() -> None:
    receiver = UdpFftReceiver(bind="127.0.0.1", port=0)
    try:
        assert receiver.socket.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF) >= 1024 * 1024
        assert receiver.socket.gettimeout() == 0.25
    finally:
        receiver.close()


def test_invalid_and_out_of_order_packets_are_visible_in_stats() -> None:
    reversed_frame = list(reversed(make_frame(7)))
    receiver = UdpFftReceiver.from_datagrams([b"invalid", *reversed_frame])

    observed = list(receiver.frames(limit=1))

    assert observed[0].frame_id == 7
    assert receiver.stats.invalid_datagrams == 1
    assert receiver.stats.out_of_order_chunks == 11


def test_keyboard_interrupt_stops_iteration_cleanly() -> None:
    def interrupted_datagrams():
        yield from make_frame(1)
        raise KeyboardInterrupt

    receiver = UdpFftReceiver.from_datagrams(interrupted_datagrams())

    assert [response.frame_id for response in receiver.frames()] == [1]


def test_timeout_advances_expiry_and_allows_idle_stop() -> None:
    class TimeoutAfterDatagram:
        def __init__(self) -> None:
            self._datagram = make_frame(12)[0]

        def recvfrom(self, _size: int):
            if self._datagram is not None:
                datagram, self._datagram = self._datagram, None
                return datagram, None
            raise socket.timeout

        def close(self) -> None:
            pass

    timestamps = iter([0.0, 1.1])
    receiver = UdpFftReceiver(
        _source=TimeoutAfterDatagram(),
        _clock=lambda: next(timestamps),
    )

    observed = list(receiver.frames(on_idle=lambda: True))

    assert observed == []
    assert receiver.stats.packets_received == 1
    assert receiver.stats.lost_frames == 1
