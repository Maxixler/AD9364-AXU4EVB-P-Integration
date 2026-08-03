import struct

import numpy as np
import pytest

from PROJECT.ethernet_fft.protocol import HEADER, UdpFftChunk, UdpProtocolError


def make_datagram(
    *,
    frame_id=0x01020304,
    chunk_index=0,
    first_bin=None,
    bins=None,
    chunk_count=12,
    fft_size=2048,
):
    if first_bin is None:
        first_bin = chunk_index * 176
    if bins is None:
        bins = np.arange(min(176, fft_size - first_bin), dtype="<u8")
    bins = np.asarray(bins, dtype="<u8")
    header = HEADER.pack(
        0x41464654, 1, 1, 64, frame_id, chunk_index, chunk_count,
        first_bin, bins.size, fft_size, 0x1234, 2_400_000_000,
        30_720_000, 10_000_000, 50, 20, 0x0102030405060708,
        0x89ABCDEF, -17, 19, 3, 0, 1,
    )
    return header + bins.tobytes()


def corrupt_valid_datagram(mutation):
    datagram = bytearray(make_datagram())
    if mutation == "magic":
        datagram[0] ^= 0xFF
    elif mutation == "version":
        datagram[4] = 2
    elif mutation == "length":
        datagram[6:8] = struct.pack("!H", 63)
    elif mutation == "range":
        datagram[16:18] = struct.pack("!H", 1)
    else:
        raise AssertionError(f"unknown mutation: {mutation}")
    return bytes(datagram)


def test_header_matches_64_byte_c_wire_layout():
    assert HEADER.format == "!IBBHIHHHHHHQIIhHQIhhHBB"
    assert HEADER.size == 64


def test_decodes_exact_c_wire_bytes():
    header = bytes.fromhex(
        "414646540101004001020304000b000c0790007008001234"
        "000000008f0d180001d4c0000098968000320014"
        "010203040506070889abcdefffeF001300030001"
    )
    datagram = header + bytes(112 * 8)

    chunk = UdpFftChunk.decode(datagram)

    assert chunk.frame_id == 0x01020304
    assert chunk.chunk_index == 11
    assert chunk.first_bin == 1936
    assert chunk.bins.size == 112
    assert chunk.bins[0] == 0


def test_decodes_last_chunk():
    bins = np.arange(112, dtype="<u8")
    datagram = make_datagram(
        frame_id=0x01020304, chunk_index=11, first_bin=1936, bins=bins
    )

    chunk = UdpFftChunk.decode(datagram)

    assert chunk.frame_id == 0x01020304
    assert chunk.chunk_index == 11
    assert chunk.first_bin == 1936
    assert chunk.bin_count == 112
    assert chunk.bins.dtype == np.dtype("<u8")
    np.testing.assert_array_equal(chunk.bins, bins)
    assert chunk.flags == 0x1234
    assert chunk.lo_hz == 2_400_000_000
    assert chunk.gain_db == 50
    assert chunk.peak_power == 0x0102030405060708


@pytest.mark.parametrize("mutation", ["magic", "version", "length", "range"])
def test_rejects_invalid_datagram(mutation):
    with pytest.raises(UdpProtocolError):
        UdpFftChunk.decode(corrupt_valid_datagram(mutation))


@pytest.mark.parametrize(
    "datagram",
    [
        b"",
        make_datagram(chunk_count=11),
        make_datagram(fft_size=1024),
        make_datagram(chunk_index=12, first_bin=2112, bins=np.array([], dtype="<u8")),
        make_datagram(chunk_index=1, first_bin=176, bins=np.arange(175, dtype="<u8")),
        make_datagram()[:-1],
    ],
    ids=["short-header", "wrong-chunk-count", "wrong-fft-size", "chunk-index", "wrong-bin-count", "truncated-payload"],
)
def test_rejects_all_invalid_wire_contracts(datagram):
    with pytest.raises(UdpProtocolError):
        UdpFftChunk.decode(datagram)
