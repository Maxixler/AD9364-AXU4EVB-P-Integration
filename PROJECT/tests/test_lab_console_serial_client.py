import struct
import unittest
import zlib

import numpy as np

from PROJECT.lab_console.protocol import (
    ERROR,
    ERROR_PAYLOAD,
    HEADER,
    INFO,
    INFO_PREFIX,
    PROTOCOL_VERSION,
    RESPONSE_MAGIC,
    SPECTRUM,
    SPECTRUM_PREFIX,
)
from PROJECT.lab_console.serial_client import (
    BoardError,
    CaptureConfig,
    LabSerialClient,
    TransportTimeout,
)


def response_wire(
    message_type: int, sequence: int, payload: bytes
) -> bytes:
    prefix = HEADER.pack(
        RESPONSE_MAGIC,
        PROTOCOL_VERSION,
        message_type,
        0,
        len(payload),
        sequence,
    ) + payload
    return prefix + struct.pack("<I", zlib.crc32(prefix) & 0xFFFFFFFF)


def info_wire(sequence: int) -> bytes:
    payload = INFO_PREFIX.pack(
        1,
        1,
        0x00010000,
        7,
        2048,
        8,
        1,
        30_720_000,
        10_000_000,
        2_400_000_000,
        b"monopulse-live-lab-v1".ljust(32, b"\0"),
    )
    return response_wire(INFO, sequence, payload)


def spectrum_wire(sequence: int) -> bytes:
    bins = np.zeros(2048, dtype=np.uint64)
    bins[5] = 1234
    prefix = SPECTRUM_PREFIX.pack(
        9,
        2048,
        2048,
        30_720_000,
        10_000_000,
        2_400_000_000,
        0xAABBCCDD,
        7,
        1234,
        5,
        -10,
        20,
        2,
        0,
        1,
        0,
        0,
    )
    return response_wire(SPECTRUM, sequence, prefix + bins.tobytes())


class FakeSerial:
    def __init__(
        self,
        responses: list[bytes],
        *,
        chunk_size: int = 4096,
    ) -> None:
        self._responses = list(responses)
        self._pending = bytearray()
        self.chunk_size = chunk_size
        self.writes: list[bytes] = []
        self.is_open = True

    def write(self, data: bytes) -> int:
        wire = bytes(data)
        self.writes.append(wire)
        if self._responses:
            self._pending.extend(self._responses.pop(0))
        return len(wire)

    def read(self, size: int) -> bytes:
        count = min(size, self.chunk_size, len(self._pending))
        if count == 0:
            return b""
        result = bytes(self._pending[:count])
        del self._pending[:count]
        return result

    def close(self) -> None:
        self.is_open = False


class StepClock:
    def __init__(self, step: float) -> None:
        self.value = -step
        self.step = step

    def __call__(self) -> float:
        self.value += self.step
        return self.value


def make_client(
    fake: FakeSerial,
    *,
    clock: StepClock | None = None,
    retries: int = 1,
) -> LabSerialClient:
    return LabSerialClient(
        "COM_TEST",
        serial_factory=lambda **_: fake,
        clock=clock or StepClock(0.0001),
        retries=retries,
    )


class LabSerialClientTests(unittest.TestCase):
    def test_sequences_increment_and_fragmented_noise_is_ignored(self) -> None:
        fake = FakeSerial(
            [
                b"PL_FFT_LAB: READY\r\n" + info_wire(1),
                spectrum_wire(2),
            ],
            chunk_size=3,
        )

        with make_client(fake) as client:
            info = client.get_info()
            spectrum = client.capture_once(CaptureConfig())

        self.assertEqual(info.sequence, 1)
        self.assertEqual(spectrum.sequence, 2)
        self.assertEqual(
            [struct.unpack_from("<I", item, 12)[0] for item in fake.writes],
            [1, 2],
        )
        self.assertFalse(fake.is_open)

    def test_unrelated_older_sequence_is_ignored(self) -> None:
        fake = FakeSerial([info_wire(99) + info_wire(1)])

        with make_client(fake) as client:
            info = client.get_info()

        self.assertEqual(info.sequence, 1)
        self.assertEqual(len(fake.writes), 1)

    def test_bad_crc_is_discarded_and_retried_once_with_same_sequence(
        self,
    ) -> None:
        corrupt = bytearray(info_wire(1))
        corrupt[-1] ^= 0x80
        fake = FakeSerial([bytes(corrupt), info_wire(1)])

        with make_client(fake) as client:
            info = client.get_info()

        self.assertEqual(info.sequence, 1)
        self.assertEqual(len(fake.writes), 2)
        self.assertEqual(fake.writes[0], fake.writes[1])

    def test_five_second_deadline_retries_once_then_times_out(self) -> None:
        fake = FakeSerial([b"", b""])

        with make_client(fake, clock=StepClock(1.0)) as client:
            with self.assertRaisesRegex(TransportTimeout, "5.0"):
                client.get_info()

        self.assertEqual(len(fake.writes), 2)

    def test_board_error_is_raised_without_retry(self) -> None:
        wire = response_wire(
            ERROR,
            1,
            ERROR_PAYLOAD.pack(-6, 4, 0),
        )
        fake = FakeSerial([wire])

        with make_client(fake) as client:
            with self.assertRaises(BoardError) as raised:
                client.get_info()

        self.assertEqual(raised.exception.error.error_code, -6)
        self.assertEqual(raised.exception.error.stage, 4)
        self.assertEqual(len(fake.writes), 1)


if __name__ == "__main__":
    unittest.main()
