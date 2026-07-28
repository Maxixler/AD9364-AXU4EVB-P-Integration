import struct
import unittest
import zlib

import numpy as np

from PROJECT.lab_console.protocol import (
    CAPTURE_ONCE,
    ERROR,
    GET_INFO,
    HEADER,
    INFO,
    INFO_PREFIX,
    MAX_PAYLOAD,
    PROTOCOL_VERSION,
    RESPONSE_MAGIC,
    SPECTRUM,
    SPECTRUM_PREFIX,
    Envelope,
    MessageDecoder,
    ProtocolError,
    decode_error,
    decode_info,
    decode_spectrum,
    encode_capture_once,
    encode_get_info,
)


def make_response(
    message_type: int,
    sequence: int,
    payload: bytes = b"",
    *,
    version: int = PROTOCOL_VERSION,
    flags: int = 0,
) -> bytes:
    prefix = HEADER.pack(
        RESPONSE_MAGIC,
        version,
        message_type,
        flags,
        len(payload),
        sequence,
    ) + payload
    return prefix + struct.pack("<I", zlib.crc32(prefix) & 0xFFFFFFFF)


class LabConsoleProtocolEncodingTests(unittest.TestCase):
    def test_protocol_v2_binds_manual_gain_telemetry(self) -> None:
        self.assertEqual(PROTOCOL_VERSION, 2)
        self.assertEqual(INFO_PREFIX.size, 68)
        self.assertEqual(SPECTRUM_PREFIX.size, 56)

    def test_get_info_has_exact_v2_wire_image(self) -> None:
        expected_without_crc = bytes.fromhex(
            "4d504c51020100000000000001000000"
        )
        expected = expected_without_crc + struct.pack(
            "<I", zlib.crc32(expected_without_crc) & 0xFFFFFFFF
        )

        self.assertEqual(encode_get_info(1), expected)

    def test_capture_once_has_exact_v2_payload(self) -> None:
        payload = struct.pack("<HHHBB", 12, 1999, 4, 3, 0)
        prefix = HEADER.pack(
            b"MPLQ",
            PROTOCOL_VERSION,
            CAPTURE_ONCE,
            0,
            len(payload),
            0x10203040,
        ) + payload
        expected = prefix + struct.pack(
            "<I", zlib.crc32(prefix) & 0xFFFFFFFF
        )

        self.assertEqual(
            encode_capture_once(0x10203040, 12, 1999, 4, 3),
            expected,
        )


class LabConsoleEnvelopeDecoderTests(unittest.TestCase):
    def test_one_byte_fragmentation_preserves_sequence_and_payload(self) -> None:
        wire = make_response(0x02, 0xA1B2C3D4, b"abc")
        decoder = MessageDecoder()
        decoded = []

        for byte in wire:
            decoded.extend(decoder.feed(bytes((byte,))))

        self.assertEqual(
            decoded,
            [
                Envelope(
                    message_type=0x02,
                    flags=0,
                    sequence=0xA1B2C3D4,
                    payload=b"abc",
                )
            ],
        )

    def test_text_and_noise_before_response_are_discarded(self) -> None:
        decoder = MessageDecoder()

        decoded = decoder.feed(
            b"PL_FFT_LAB: READY\r\n\x00\xff"
            + make_response(0x02, 7, b"ok")
        )

        self.assertEqual(decoded[0].sequence, 7)
        self.assertEqual(decoded[0].payload, b"ok")

    def test_corrupt_crc_is_rejected_and_next_message_resynchronizes(self) -> None:
        corrupt = bytearray(make_response(0x02, 7, b"bad"))
        corrupt[-1] ^= 0x80
        good = make_response(0x02, 8, b"good")
        decoder = MessageDecoder()

        decoded = decoder.feed(bytes(corrupt) + good)

        self.assertEqual([item.sequence for item in decoded], [8])
        self.assertEqual(decoder.crc_error_count, 1)

    def test_unknown_version_is_rejected_without_losing_next_message(self) -> None:
        decoder = MessageDecoder()

        decoded = decoder.feed(
            make_response(0x02, 3, version=1)
            + make_response(0x02, 4)
        )

        self.assertEqual([item.sequence for item in decoded], [4])
        self.assertEqual(decoder.protocol_error_count, 1)

    def test_oversized_declared_payload_is_bounded_and_resynchronizes(self) -> None:
        oversized_header = HEADER.pack(
            RESPONSE_MAGIC,
            PROTOCOL_VERSION,
            0x02,
            0,
            MAX_PAYLOAD + 1,
            10,
        )
        decoder = MessageDecoder()

        decoded = decoder.feed(
            oversized_header
            + b"x" * 32
            + make_response(0x02, 11, b"bounded")
        )

        self.assertEqual([item.sequence for item in decoded], [11])
        self.assertLessEqual(
            decoder.buffered_bytes,
            HEADER.size + MAX_PAYLOAD + 4,
        )

    def test_truncated_message_waits_for_remaining_bytes(self) -> None:
        wire = make_response(0x02, 12, b"fragment")
        decoder = MessageDecoder()

        self.assertEqual(decoder.feed(wire[:-2]), [])
        decoded = decoder.feed(wire[-2:])

        self.assertEqual(decoded[0].sequence, 12)
        self.assertEqual(decoded[0].payload, b"fragment")


class LabConsolePayloadDecoderTests(unittest.TestCase):
    def test_info_decodes_every_runtime_and_release_field(self) -> None:
        payload = INFO_PREFIX.pack(
            1,
            1,
            0x00010000,
            0x00000007,
            2048,
            8,
            1,
            30_720_000,
            10_000_000,
            2_400_000_000,
            50,
            0,
            0,
            b"monopulse-live-lab-v2".ljust(32, b"\0"),
        )
        envelope = Envelope(INFO, 0, 19, payload)

        info = decode_info(envelope)

        self.assertEqual(info.sequence, 19)
        self.assertEqual(info.board_code, 1)
        self.assertEqual(info.rf_device_code, 1)
        self.assertEqual(info.firmware_version, 0x00010000)
        self.assertEqual(info.feature_bits, 0x7)
        self.assertEqual(info.fft_size, 2048)
        self.assertEqual(info.spectrum_word_bytes, 8)
        self.assertEqual(info.rf_state_count, 1)
        self.assertEqual(info.sample_rate_hz, 30_720_000)
        self.assertEqual(info.rx_bandwidth_hz, 10_000_000)
        self.assertEqual(info.lo_hz, 2_400_000_000)
        self.assertEqual(info.gain_db, 50)
        self.assertEqual(info.gain_mode, 0)
        self.assertEqual(info.release_id, "monopulse-live-lab-v2")

    def test_info_rejects_reserved_feature_bits(self) -> None:
        payload = INFO_PREFIX.pack(
            1,
            1,
            0x00010000,
            0x80000007,
            2048,
            8,
            1,
            30_720_000,
            10_000_000,
            2_400_000_000,
            50,
            0,
            0,
            b"candidate".ljust(32, b"\0"),
        )

        with self.assertRaisesRegex(ProtocolError, "feature"):
            decode_info(Envelope(INFO, 0, 1, payload))

    def test_spectrum_decodes_exact_bins_signed_peak_and_hardware_flags(
        self,
    ) -> None:
        bins = np.arange(2048, dtype=np.uint64)
        prefix = SPECTRUM_PREFIX.pack(
            41,
            2048,
            2048,
            30_720_000,
            10_000_000,
            2_400_000_000,
            0xAABBCCDD,
            1234,
            987654321,
            88,
            -123,
            456,
            9,
            3,
            1,
            0b001001,
            50,
            0,
            0,
        )
        envelope = Envelope(SPECTRUM, 0, 23, prefix + bins.tobytes())

        response = decode_spectrum(envelope)

        self.assertEqual(response.sequence, 23)
        self.assertEqual(response.frame_id, 41)
        self.assertEqual(response.sample_count, 2048)
        self.assertEqual(response.fft_size, 2048)
        self.assertEqual(response.sample_rate_hz, 30_720_000)
        self.assertEqual(response.rx_bandwidth_hz, 10_000_000)
        self.assertEqual(response.lo_hz, 2_400_000_000)
        self.assertEqual(response.frame_crc32, 0xAABBCCDD)
        self.assertEqual(response.skipped_sample_count, 1234)
        self.assertEqual(response.peak_power, 987654321)
        self.assertEqual(response.peak_bin, 88)
        self.assertEqual(response.peak_re, -123)
        self.assertEqual(response.peak_im, 456)
        self.assertEqual(response.reset_epoch, 9)
        self.assertEqual(response.rf_state, 3)
        self.assertEqual(response.active_bank, 1)
        self.assertEqual(response.hardware_flags, 0b001001)
        self.assertEqual(response.gain_db, 50)
        self.assertEqual(response.gain_mode, 0)
        self.assertEqual(
            response.hardware_faults,
            ("frame_error", "cdc_fault"),
        )
        self.assertEqual(response.spectrum.dtype, np.dtype("<u8"))
        self.assertEqual(response.spectrum.shape, (2048,))
        self.assertEqual(int(response.spectrum[-1]), 2047)

    def test_spectrum_rejects_wrong_payload_length_and_reserved_word(
        self,
    ) -> None:
        bins = np.zeros(2048, dtype=np.uint64).tobytes()
        valid_prefix = SPECTRUM_PREFIX.pack(
            1,
            2048,
            2048,
            30_720_000,
            10_000_000,
            2_400_000_000,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            50,
            0,
            0,
        )
        with self.assertRaisesRegex(ProtocolError, "length"):
            decode_spectrum(
                Envelope(SPECTRUM, 0, 1, valid_prefix + bins[:-8])
            )

        reserved_prefix = bytearray(valid_prefix)
        reserved_prefix[-1] = 1
        with self.assertRaisesRegex(ProtocolError, "reserved"):
            decode_spectrum(
                Envelope(SPECTRUM, 0, 1, bytes(reserved_prefix) + bins)
            )

    def test_spectrum_rejects_non_2048_contract(self) -> None:
        bins = np.zeros(2048, dtype=np.uint64).tobytes()
        prefix = SPECTRUM_PREFIX.pack(
            1,
            1024,
            2048,
            30_720_000,
            10_000_000,
            2_400_000_000,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            50,
            0,
            0,
        )

        with self.assertRaisesRegex(ProtocolError, "sample_count"):
            decode_spectrum(Envelope(SPECTRUM, 0, 1, prefix + bins))

    def test_error_decodes_signed_code_and_rejects_nonzero_detail(self) -> None:
        response = decode_error(
            Envelope(ERROR, 0, 37, struct.pack("<iHH", -6, 4, 0))
        )

        self.assertEqual(response.sequence, 37)
        self.assertEqual(response.error_code, -6)
        self.assertEqual(response.stage, 4)
        self.assertEqual(response.detail, 0)

        with self.assertRaisesRegex(ProtocolError, "detail"):
            decode_error(
                Envelope(ERROR, 0, 37, struct.pack("<iHH", -6, 4, 1))
            )

    def test_payload_decoder_rejects_wrong_message_type(self) -> None:
        with self.assertRaisesRegex(ProtocolError, "message type"):
            decode_error(Envelope(INFO, 0, 1, struct.pack("<iHH", -1, 1, 0)))


if __name__ == "__main__":
    unittest.main()
