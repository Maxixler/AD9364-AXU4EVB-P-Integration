#include <stdint.h>
#include <stdio.h>

#include "pl_fft_udp_protocol.h"

static int failures;

#define CHECK(condition) do { \
	if (!(condition)) { \
		printf("FAIL line=%d condition=%s\n", __LINE__, #condition); \
		failures++; \
		return; \
	} \
} while (0)

static void test_header_and_chunk_contract(void)
{
	uint8_t bytes[PL_FFT_UDP_HEADER_BYTES];
	struct pl_fft_udp_chunk_view last;
	struct pl_fft_udp_metadata meta = {
		.frame_id = 0x01020304u,
		.hardware_flags = 0x1122u,
		.lo_hz = 2400000000ull,
		.sample_rate_hz = 30720000u,
		.bandwidth_hz = 10000000u,
		.gain_db = 50,
		.peak_bin = 20u,
		.peak_power = 0x0102030405060708ull,
		.frame_crc32 = 0xaabbccddu,
		.peak_re = -123,
		.peak_im = 456,
		.reset_epoch = 7u,
		.rf_state = 0u,
		.active_bank = 1u,
	};

	CHECK(pl_fft_udp_chunk_bounds(11u, &last) == PL_FFT_UDP_OK);
	CHECK(last.first_bin == 1936u);
	CHECK(last.bin_count == 112u);
	CHECK(pl_fft_udp_encode_header(bytes, &meta, 11u) == PL_FFT_UDP_OK);
	CHECK(bytes[0] == 'A' && bytes[1] == 'F' &&
	      bytes[2] == 'F' && bytes[3] == 'T');
	CHECK(bytes[4] == 1u && bytes[5] == 1u);
	CHECK(bytes[6] == 0u && bytes[7] == 64u);
	CHECK(bytes[8] == 1u && bytes[9] == 2u &&
	      bytes[10] == 3u && bytes[11] == 4u);
	CHECK(bytes[12] == 0u && bytes[13] == 11u);
	CHECK(bytes[14] == 0u && bytes[15] == 12u);
	CHECK(bytes[16] == 7u && bytes[17] == 144u);
	CHECK(bytes[18] == 0u && bytes[19] == 112u);
	CHECK(bytes[20] == 8u && bytes[21] == 0u);
	CHECK(bytes[22] == 0x11u && bytes[23] == 0x22u);
	CHECK(bytes[24] == 0u && bytes[25] == 0u && bytes[26] == 0u &&
	      bytes[27] == 0u && bytes[28] == 0x8fu && bytes[29] == 0x0du &&
	      bytes[30] == 0x18u && bytes[31] == 0u);
	CHECK(bytes[32] == 0x01u && bytes[33] == 0xd4u &&
	      bytes[34] == 0xc0u && bytes[35] == 0u);
	CHECK(bytes[36] == 0x00u && bytes[37] == 0x98u &&
	      bytes[38] == 0x96u && bytes[39] == 0x80u);
	CHECK(bytes[40] == 0u && bytes[41] == 50u);
	CHECK(bytes[42] == 0u && bytes[43] == 20u);
	CHECK(bytes[44] == 1u && bytes[45] == 2u && bytes[46] == 3u &&
	      bytes[47] == 4u && bytes[48] == 5u && bytes[49] == 6u &&
	      bytes[50] == 7u && bytes[51] == 8u);
	CHECK(bytes[52] == 0xaau && bytes[53] == 0xbbu &&
	      bytes[54] == 0xccu && bytes[55] == 0xddu);
	CHECK(bytes[56] == 0xffu && bytes[57] == 0x85u);
	CHECK(bytes[58] == 0x01u && bytes[59] == 0xc8u);
	CHECK(bytes[60] == 0u && bytes[61] == 7u);
	CHECK(bytes[62] == 0u && bytes[63] == 1u);
}

static void test_rejects_invalid_arguments(void)
{
	uint8_t bytes[PL_FFT_UDP_HEADER_BYTES];
	struct pl_fft_udp_chunk_view view;
	struct pl_fft_udp_metadata metadata = {0};

	CHECK(pl_fft_udp_chunk_bounds(PL_FFT_UDP_CHUNK_COUNT, &view) !=
	      PL_FFT_UDP_OK);
	CHECK(pl_fft_udp_chunk_bounds(0u, NULL) != PL_FFT_UDP_OK);
	CHECK(pl_fft_udp_encode_header(NULL, &metadata, 0u) != PL_FFT_UDP_OK);
	CHECK(pl_fft_udp_encode_header(bytes, NULL, 0u) != PL_FFT_UDP_OK);
	CHECK(pl_fft_udp_encode_header(bytes, &metadata,
	      PL_FFT_UDP_CHUNK_COUNT) != PL_FFT_UDP_OK);
}

int main(void)
{
	test_header_and_chunk_contract();
	test_rejects_invalid_arguments();
	if (failures != 0) {
		printf("FAIL: pl_fft_udp_protocol failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_udp_protocol wire contract\n");
	return 0;
}
