#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pl_fft_lab_protocol.h"

struct capture_writer {
	uint8_t bytes[PL_FFT_LAB_MAX_WIRE_SIZE];
	uint32_t length;
	uint32_t max_chunk;
	uint8_t zero_progress;
};

static int failures;

#define CHECK(condition) do { \
	if (!(condition)) { \
		printf("FAIL line=%d condition=%s\n", __LINE__, #condition); \
		failures++; \
		return; \
	} \
} while (0)

static int32_t capture_write(void *context, const uint8_t *data,
			     uint32_t length, uint32_t *written)
{
	struct capture_writer *capture = context;
	uint32_t accepted = length;

	if (capture->zero_progress != 0u) {
		*written = 0u;
		return PL_FFT_LAB_OK;
	}
	if (capture->max_chunk != 0u && accepted > capture->max_chunk)
		accepted = capture->max_chunk;
	if (capture->length + accepted > sizeof(capture->bytes))
		return PL_FFT_LAB_ERR_WRITER;
	memcpy(&capture->bytes[capture->length], data, accepted);
	capture->length += accepted;
	*written = accepted;
	return PL_FFT_LAB_OK;
}

static int32_t feed_wire(struct pl_fft_lab_parser *parser,
			 const uint8_t *wire, uint32_t length,
			 struct pl_fft_lab_command *command)
{
	int32_t event = PL_FFT_LAB_COMMAND_NONE;
	uint32_t index;

	for (index = 0u; index < length; index++)
		event = pl_fft_lab_parser_push(parser, wire[index], command);
	return event;
}

static void test_python_get_info_golden_vector_parses(void)
{
	static const uint8_t request[] = {
		0x4d, 0x50, 0x4c, 0x51, 0x01, 0x01, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
		0x26, 0x67, 0xd1, 0x18
	};
	struct pl_fft_lab_parser parser;
	struct pl_fft_lab_command command;
	int32_t event;

	pl_fft_lab_parser_init(&parser);
	memset(&command, 0, sizeof(command));
	event = feed_wire(&parser, request, sizeof(request), &command);

	CHECK(event == PL_FFT_LAB_COMMAND_READY);
	CHECK(command.type == PL_FFT_LAB_GET_INFO);
	CHECK(command.sequence == 1u);
	CHECK(command.payload_length == 0u);
}

static void test_info_writer_matches_python_golden_vector(void)
{
	static const uint8_t expected[] = {
		0x4d, 0x50, 0x4c, 0x52, 0x01, 0x02, 0x00, 0x00,
		0x40, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00,
		0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
		0x07, 0x00, 0x00, 0x00, 0x00, 0x08, 0x08, 0x01,
		0x00, 0xc0, 0xd4, 0x01, 0x80, 0x96, 0x98, 0x00,
		0x00, 0x18, 0x0d, 0x8f, 0x00, 0x00, 0x00, 0x00,
		0x6d, 0x6f, 0x6e, 0x6f, 0x70, 0x75, 0x6c, 0x73,
		0x65, 0x2d, 0x6c, 0x69, 0x76, 0x65, 0x2d, 0x6c,
		0x61, 0x62, 0x2d, 0x76, 0x31, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x16, 0x3a, 0xe6, 0xe1
	};
	struct capture_writer capture;
	struct pl_fft_lab_writer writer;
	struct pl_fft_lab_info info;

	memset(&capture, 0, sizeof(capture));
	writer.context = &capture;
	writer.write = capture_write;
	memset(&info, 0, sizeof(info));
	info.board_code = 1u;
	info.rf_device_code = 1u;
	info.firmware_version = 0x00010000u;
	info.feature_bits = 0x00000007u;
	info.fft_size = 2048u;
	info.spectrum_word_bytes = 8u;
	info.rf_state_count = 1u;
	info.sample_rate_hz = 30720000u;
	info.rx_bandwidth_hz = 10000000u;
	info.lo_hz = 2400000000ull;
	memcpy(info.release_id, "monopulse-live-lab-v1", 21u);

	CHECK(pl_fft_lab_write_info(&writer, 7u, &info) ==
	      PL_FFT_LAB_OK);
	CHECK(capture.length == sizeof(expected));
	CHECK(memcmp(capture.bytes, expected, sizeof(expected)) == 0);
}

static void test_capture_command_decodes_exact_fields(void)
{
	static const uint8_t request[] = {
		0x4d, 0x50, 0x4c, 0x51, 0x01, 0x03, 0x00, 0x00,
		0x08, 0x00, 0x00, 0x00, 0x40, 0x30, 0x20, 0x10,
		0x0c, 0x00, 0xcf, 0x07, 0x04, 0x00, 0x03, 0x00,
		0x2c, 0x1c, 0x30, 0x5b
	};
	struct pl_fft_lab_parser parser;
	struct pl_fft_lab_command command;

	pl_fft_lab_parser_init(&parser);
	CHECK(feed_wire(&parser, request, sizeof(request), &command) ==
	      PL_FFT_LAB_COMMAND_READY);
	CHECK(command.type == PL_FFT_LAB_CAPTURE_ONCE);
	CHECK(command.sequence == 0x10203040u);
	CHECK(command.payload_length == 8u);
	CHECK(command.capture.search_start == 12u);
	CHECK(command.capture.search_stop == 1999u);
	CHECK(command.capture.dc_guard == 4u);
	CHECK(command.capture.rf_state == 3u);
}

static void test_parser_rejects_crc_and_reserved_then_resynchronizes(void)
{
	static const uint8_t good[] = {
		0x4d, 0x50, 0x4c, 0x51, 0x01, 0x01, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
		0x26, 0x67, 0xd1, 0x18
	};
	static const uint8_t reserved[] = {
		0x4d, 0x50, 0x4c, 0x51, 0x01, 0x03, 0x00, 0x00,
		0x08, 0x00, 0x00, 0x00, 0x40, 0x30, 0x20, 0x10,
		0x0c, 0x00, 0xcf, 0x07, 0x04, 0x00, 0x03, 0x01,
		0xba, 0x2c, 0x37, 0x2c
	};
	uint8_t corrupt[sizeof(good)];
	struct pl_fft_lab_parser parser;
	struct pl_fft_lab_command command;
	static const uint8_t noise[] = {
		'x', 'M', 'P', 'x', 'M', 'P', 'L', 'Q'
	};
	uint32_t index;

	memcpy(corrupt, good, sizeof(good));
	corrupt[sizeof(corrupt) - 1u] ^= 0x80u;
	pl_fft_lab_parser_init(&parser);
	CHECK(feed_wire(&parser, corrupt, sizeof(corrupt), &command) ==
	      PL_FFT_LAB_COMMAND_REJECTED);
	CHECK(feed_wire(&parser, good, sizeof(good), &command) ==
	      PL_FFT_LAB_COMMAND_READY);

	pl_fft_lab_parser_init(&parser);
	for (index = 0u; index < sizeof(noise); index++)
		(void)pl_fft_lab_parser_push(&parser, noise[index], &command);
	for (index = 4u; index < sizeof(good); index++)
		CHECK(pl_fft_lab_parser_push(&parser, good[index], &command) ==
		      (index + 1u == sizeof(good) ?
		       PL_FFT_LAB_COMMAND_READY :
		       PL_FFT_LAB_COMMAND_NONE));

	pl_fft_lab_parser_init(&parser);
	CHECK(feed_wire(&parser, reserved, sizeof(reserved), &command) ==
	      PL_FFT_LAB_COMMAND_REJECTED);
}

static void test_info_writer_supports_partial_and_rejects_zero_progress(void)
{
	struct capture_writer capture;
	struct pl_fft_lab_writer writer;
	struct pl_fft_lab_info info;

	memset(&capture, 0, sizeof(capture));
	capture.max_chunk = 3u;
	writer.context = &capture;
	writer.write = capture_write;
	memset(&info, 0, sizeof(info));
	info.fft_size = 2048u;
	info.spectrum_word_bytes = 8u;
	info.rf_state_count = 1u;
	CHECK(pl_fft_lab_write_info(&writer, 1u, &info) ==
	      PL_FFT_LAB_OK);
	CHECK(capture.length == 84u);

	memset(&capture, 0, sizeof(capture));
	capture.zero_progress = 1u;
	CHECK(pl_fft_lab_write_info(&writer, 1u, &info) ==
	      PL_FFT_LAB_ERR_WRITER);
}

static void test_info_writer_rejects_reserved_contract_values(void)
{
	struct capture_writer capture;
	struct pl_fft_lab_writer writer;
	struct pl_fft_lab_info info;

	memset(&capture, 0, sizeof(capture));
	writer.context = &capture;
	writer.write = capture_write;
	memset(&info, 0, sizeof(info));
	info.feature_bits = 0x80000007u;
	info.fft_size = 2048u;
	info.spectrum_word_bytes = 8u;
	info.rf_state_count = 1u;

	CHECK(pl_fft_lab_write_info(&writer, 1u, &info) ==
	      PL_FFT_LAB_ERR_ARGUMENT);
	CHECK(capture.length == 0u);
}

static void test_error_writer_matches_python_golden_vector(void)
{
	static const uint8_t expected[] = {
		0x4d, 0x50, 0x4c, 0x52, 0x01, 0x7e, 0x00, 0x00,
		0x08, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00,
		0xfa, 0xff, 0xff, 0xff, 0x04, 0x00, 0x00, 0x00,
		0x15, 0x30, 0xd7, 0xf5
	};
	struct capture_writer capture;
	struct pl_fft_lab_writer writer;

	memset(&capture, 0, sizeof(capture));
	writer.context = &capture;
	writer.write = capture_write;
	CHECK(pl_fft_lab_write_error(&writer, 9u, -6, 4u) ==
	      PL_FFT_LAB_OK);
	CHECK(capture.length == sizeof(expected));
	CHECK(memcmp(capture.bytes, expected, sizeof(expected)) == 0);
}

static void test_spectrum_writer_streams_all_2048_words(void)
{
	struct capture_writer capture;
	struct pl_fft_lab_writer writer;
	struct pl_fft_lab_spectrum spectrum;
	uint64_t bins[PL_FFT_LAB_SPECTRUM_WORDS];
	uint32_t index;
	uint32_t crc;
	uint32_t received_crc;
	uint32_t last = PL_FFT_LAB_HEADER_SIZE + 54u +
			(PL_FFT_LAB_SPECTRUM_WORDS - 1u) * 8u;

	memset(&capture, 0, sizeof(capture));
	capture.max_chunk = 5u;
	writer.context = &capture;
	writer.write = capture_write;
	memset(&spectrum, 0, sizeof(spectrum));
	spectrum.frame_id = 41u;
	spectrum.sample_count = 2048u;
	spectrum.fft_size = 2048u;
	spectrum.sample_rate_hz = 30720000u;
	spectrum.rx_bandwidth_hz = 10000000u;
	spectrum.lo_hz = 2400000000ull;
	spectrum.frame_crc32 = 0xaabbccddu;
	spectrum.skipped_sample_count = 1234u;
	spectrum.peak_power = 987654321ull;
	spectrum.peak_bin = 88u;
	spectrum.peak_re = -123;
	spectrum.peak_im = 456;
	spectrum.reset_epoch = 9u;
	spectrum.rf_state = 3u;
	spectrum.active_bank = 1u;
	spectrum.hardware_flags = 9u;
	for (index = 0u; index < PL_FFT_LAB_SPECTRUM_WORDS; index++)
		bins[index] = 0x1122334400000000ull + index;

	CHECK(pl_fft_lab_write_spectrum(&writer, 23u, &spectrum, bins) ==
	      PL_FFT_LAB_OK);
	CHECK(capture.length == PL_FFT_LAB_HEADER_SIZE + 54u +
	      PL_FFT_LAB_SPECTRUM_WORDS * 8u + PL_FFT_LAB_CRC_SIZE);
	CHECK(capture.bytes[last + 0u] == 0xffu);
	CHECK(capture.bytes[last + 1u] == 0x07u);
	CHECK(capture.bytes[last + 4u] == 0x44u);
	CHECK(capture.bytes[last + 5u] == 0x33u);
	CHECK(capture.bytes[last + 6u] == 0x22u);
	CHECK(capture.bytes[last + 7u] == 0x11u);
	crc = pl_fft_lab_crc32_update(
		0xffffffffu, capture.bytes, capture.length - 4u) ^
		0xffffffffu;
	received_crc = (uint32_t)capture.bytes[capture.length - 4u] |
		((uint32_t)capture.bytes[capture.length - 3u] << 8) |
		((uint32_t)capture.bytes[capture.length - 2u] << 16) |
		((uint32_t)capture.bytes[capture.length - 1u] << 24);
	CHECK(crc == received_crc);
}

int main(void)
{
	test_python_get_info_golden_vector_parses();
	test_info_writer_matches_python_golden_vector();
	test_capture_command_decodes_exact_fields();
	test_parser_rejects_crc_and_reserved_then_resynchronizes();
	test_info_writer_supports_partial_and_rejects_zero_progress();
	test_info_writer_rejects_reserved_contract_values();
	test_error_writer_matches_python_golden_vector();
	test_spectrum_writer_streams_all_2048_words();

	if (failures != 0) {
		printf("FAIL: pl_fft_lab_protocol failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_lab_protocol golden vectors\n");
	return 0;
}
