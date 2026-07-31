import numpy as np

from PROJECT.ethernet_fft.protocol import HEADER
from PROJECT.ethernet_fft.reassembly import FrameReassembler


def make_frame(
    frame_id: int,
    *,
    flags: int = 0x1234,
    frame_crc32: int = 0x89ABCDEF,
) -> list[bytes]:
    datagrams = []
    for chunk_index in range(12):
        first_bin = chunk_index * 176
        bin_count = min(176, 2048 - first_bin)
        bins = np.arange(first_bin, first_bin + bin_count, dtype="<u8")
        header = HEADER.pack(
            0x41464654,
            1,
            1,
            64,
            frame_id,
            chunk_index,
            12,
            first_bin,
            bin_count,
            2048,
            flags,
            2_400_000_000,
            30_720_000,
            10_000_000,
            50,
            20,
            0x0102030405060708,
            frame_crc32,
            -17,
            19,
            3,
            0,
            1,
        )
        datagrams.append(header + bins.tobytes())
    return datagrams


def test_reassembles_twelve_chunks_in_reverse_order() -> None:
    assembler = FrameReassembler(timeout_s=1.0)

    response = None
    for datagram in reversed(make_frame(frame_id=7)):
        response = assembler.push(datagram, received_at=0.1)

    assert response is not None
    assert response.sequence == 7
    assert response.frame_id == 7
    assert response.peak_bin == 20
    assert response.frame_crc32 == 0x89ABCDEF
    assert response.hardware_flags == 0x1234
    np.testing.assert_array_equal(
        response.spectrum, np.arange(2048, dtype=np.uint64)
    )
    assert assembler.completed_frames == 1
    assert assembler.out_of_order_chunks > 0


def test_duplicate_chunk_is_counted_without_preventing_completion() -> None:
    assembler = FrameReassembler(timeout_s=1.0)
    datagrams = make_frame(frame_id=8)

    assert assembler.push(datagrams[0], received_at=0.0) is None
    assert assembler.push(datagrams[0], received_at=0.1) is None
    response = None
    for datagram in datagrams[1:]:
        response = assembler.push(datagram, received_at=0.2)

    assert response is not None
    assert assembler.duplicate_chunks == 1
    assert assembler.completed_frames == 1


def test_inconsistent_metadata_discards_the_pending_frame() -> None:
    assembler = FrameReassembler(timeout_s=1.0)
    clean = make_frame(frame_id=9)
    mismatched = make_frame(frame_id=9, flags=0x4321)

    assert assembler.push(clean[0], received_at=0.0) is None
    assert assembler.push(mismatched[1], received_at=0.1) is None
    response = None
    for datagram in clean[1:]:
        response = assembler.push(datagram, received_at=0.2)

    assert response is None
    assert assembler.invalid_datagrams == 1
    assert assembler.completed_frames == 0


def test_expires_incomplete_frame_without_plotting_it() -> None:
    assembler = FrameReassembler(timeout_s=1.0)

    assembler.push(make_frame(10)[0], received_at=0.0)

    assert assembler.expire(now=1.1) == 1
    assert assembler.lost_frames == 1
    assert assembler.completed_frames == 0


def test_evicts_oldest_incomplete_frame_when_eight_are_pending() -> None:
    assembler = FrameReassembler(timeout_s=10.0)
    oldest = make_frame(100)

    assert assembler.push(oldest[0], received_at=0.0) is None
    for frame_id in range(101, 109):
        assert assembler.push(make_frame(frame_id)[0], received_at=float(frame_id)) is None

    response = None
    for datagram in make_frame(108)[1:]:
        response = assembler.push(datagram, received_at=109.0)

    assert response is not None
    assert response.frame_id == 108
    for datagram in make_frame(101)[1:]:
        response = assembler.push(datagram, received_at=109.0)

    assert response is not None
    assert response.frame_id == 101
    for datagram in oldest[1:]:
        response = assembler.push(datagram, received_at=109.0)

    assert response is None
    assert assembler.lost_frames == 1
    assert assembler.completed_frames == 2


def test_invalid_datagram_is_counted_and_discarded() -> None:
    assembler = FrameReassembler(timeout_s=1.0)

    assert assembler.push(b"not an FFT datagram", received_at=0.0) is None

    assert assembler.invalid_datagrams == 1
