#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pl_fft_lab_service.h"

struct test_context {
	uint8_t wire[PL_FFT_LAB_MAX_WIRE_SIZE];
	uint32_t wire_length;
	struct pl_fft_lab_rf_snapshot rf;
	int32_t rf_status;
	int32_t capture_status;
	struct pl_fft_result capture_result;
	uint32_t capture_calls;
	uint16_t search_start;
	uint16_t search_stop;
	uint16_t dc_guard;
	uint8_t rf_state;
};

static int failures;

#define CHECK(condition) do { \
	if (!(condition)) { \
		printf("FAIL line=%d condition=%s\n", __LINE__, #condition); \
		failures++; \
		return; \
	} \
} while (0)

static int32_t test_write(void *context, const uint8_t *data,
			  uint32_t length, uint32_t *written)
{
	struct test_context *test = context;

	if (test->wire_length + length > sizeof(test->wire))
		return PL_FFT_LAB_ERR_WRITER;
	memcpy(&test->wire[test->wire_length], data, length);
	test->wire_length += length;
	*written = length;
	return PL_FFT_LAB_OK;
}

static int32_t test_read_rf(void *context,
			    struct pl_fft_lab_rf_snapshot *snapshot)
{
	struct test_context *test = context;

	if (test->rf_status != PL_FFT_OK)
		return test->rf_status;
	*snapshot = test->rf;
	return PL_FFT_OK;
}

int pl_fft_init(struct pl_fft_device *dev)
{
	(void)dev;
	return PL_FFT_OK;
}

int pl_fft_capture_once(struct pl_fft_device *dev,
			uint16_t search_start, uint16_t search_stop,
			uint16_t dc_guard, uint8_t rf_state,
			struct pl_fft_result *result,
			uint64_t spectrum[PL_FFT_SPECTRUM_WORDS])
{
	struct test_context *test = dev->context;
	uint32_t index;

	test->capture_calls++;
	test->search_start = search_start;
	test->search_stop = search_stop;
	test->dc_guard = dc_guard;
	test->rf_state = rf_state;
	if (test->capture_status != PL_FFT_OK)
		return test->capture_status;
	*result = test->capture_result;
	for (index = 0u; index < PL_FFT_SPECTRUM_WORDS; index++)
		spectrum[index] = 0x1122334400000000ull + index;
	return PL_FFT_OK;
}

int pl_fft_result_crc_matches(const struct pl_fft_result *result,
			      uint32_t expected_crc)
{
	return result != NULL && result->frame_crc32 == expected_crc;
}

static struct pl_fft_lab_service make_service(
	struct test_context *test, uint64_t *spectrum)
{
	static struct pl_fft_device fft;
	struct pl_fft_lab_service service;

	memset(&fft, 0, sizeof(fft));
	fft.context = test;
	memset(&service, 0, sizeof(service));
	service.fft = &fft;
	service.writer.context = test;
	service.writer.write = test_write;
	service.rf_context = test;
	service.read_rf = test_read_rf;
	service.spectrum = spectrum;
	return service;
}

static void test_get_info_matches_exact_python_vector(void)
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
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	memset(&test, 0, sizeof(test));
	test.rf.sample_rate_hz = 30720000u;
	test.rf.rx_bandwidth_hz = 10000000u;
	test.rf.lo_hz = 2400000000ull;
	test.rf_status = PL_FFT_OK;
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_GET_INFO;
	command.sequence = 7u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.wire_length == sizeof(expected));
	CHECK(memcmp(test.wire, expected, sizeof(expected)) == 0);
}

static uint16_t get_u16_le(const uint8_t *value)
{
	return (uint16_t)((uint16_t)value[0] |
			  ((uint16_t)value[1] << 8));
}

static uint32_t get_u32_le(const uint8_t *value)
{
	return (uint32_t)value[0] |
	       ((uint32_t)value[1] << 8) |
	       ((uint32_t)value[2] << 16) |
	       ((uint32_t)value[3] << 24);
}

static uint64_t get_u64_le(const uint8_t *value)
{
	return (uint64_t)get_u32_le(value) |
	       ((uint64_t)get_u32_le(&value[4]) << 32);
}

static void initialize_capture_context(struct test_context *test)
{
	memset(test, 0, sizeof(*test));
	test->rf.sample_rate_hz = 30720000u;
	test->rf.rx_bandwidth_hz = 10000000u;
	test->rf.lo_hz = 2400000000ull;
	test->rf_status = PL_FFT_OK;
	test->capture_status = PL_FFT_OK;
	test->capture_result.frame_id = 41u;
	test->capture_result.sample_count = 2048u;
	test->capture_result.frame_crc32 = 0xaabbccddu;
	test->capture_result.dropped_count = 1234u;
	test->capture_result.peak_power = 987654321ull;
	test->capture_result.reset_epoch = 9u;
	test->capture_result.peak_bin = 88u;
	test->capture_result.peak_re = -123;
	test->capture_result.peak_im = 456;
	test->capture_result.active_bank = 1u;
	test->capture_result.rf_state = 3u;
	test->capture_result.hardware_flags = 0u;
}

static void test_rf_readback_failure_returns_config_error(void)
{
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	initialize_capture_context(&test);
	test.rf_status = PL_FFT_ERR_HARDWARE;
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_GET_INFO;
	command.sequence = 17u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.wire[5] == PL_FFT_LAB_ERROR);
	CHECK(get_u32_le(&test.wire[12]) == 17u);
	CHECK((int32_t)get_u32_le(&test.wire[16]) ==
	      PL_FFT_ERR_HARDWARE);
	CHECK(get_u16_le(&test.wire[20]) ==
	      PL_FFT_LAB_STAGE_CONFIG);
}

static void test_capture_forwards_config_and_streams_exact_metadata(void)
{
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t payload = PL_FFT_LAB_HEADER_SIZE;
	uint32_t last = payload + 54u +
			(PL_FFT_SPECTRUM_WORDS - 1u) * 8u;

	initialize_capture_context(&test);
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_CAPTURE_ONCE;
	command.sequence = 23u;
	command.payload_length = 8u;
	command.capture.search_start = 12u;
	command.capture.search_stop = 1999u;
	command.capture.dc_guard = 4u;
	command.capture.rf_state = 3u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.capture_calls == 1u);
	CHECK(test.search_start == 12u);
	CHECK(test.search_stop == 1999u);
	CHECK(test.dc_guard == 4u);
	CHECK(test.rf_state == 3u);
	CHECK(test.wire[5] == PL_FFT_LAB_SPECTRUM);
	CHECK(get_u32_le(&test.wire[12]) == 23u);
	CHECK(get_u32_le(&test.wire[payload + 0u]) == 41u);
	CHECK(get_u16_le(&test.wire[payload + 4u]) == 2048u);
	CHECK(get_u16_le(&test.wire[payload + 6u]) == 2048u);
	CHECK(get_u32_le(&test.wire[payload + 8u]) == 30720000u);
	CHECK(get_u32_le(&test.wire[payload + 12u]) == 10000000u);
	CHECK(get_u64_le(&test.wire[payload + 16u]) == 2400000000ull);
	CHECK(get_u32_le(&test.wire[payload + 24u]) == 0xaabbccddu);
	CHECK(get_u32_le(&test.wire[payload + 28u]) == 1234u);
	CHECK(get_u64_le(&test.wire[payload + 32u]) == 987654321ull);
	CHECK(get_u16_le(&test.wire[payload + 40u]) == 88u);
	CHECK((int16_t)get_u16_le(&test.wire[payload + 42u]) == -123);
	CHECK((int16_t)get_u16_le(&test.wire[payload + 44u]) == 456);
	CHECK(get_u16_le(&test.wire[payload + 46u]) == 9u);
	CHECK(test.wire[payload + 48u] == 3u);
	CHECK(test.wire[payload + 49u] == 1u);
	CHECK(get_u16_le(&test.wire[payload + 50u]) == 0u);
	CHECK(get_u64_le(&test.wire[last]) ==
	      0x11223344000007ffull);
}

static void expect_capture_error(int32_t capture_status,
				 uint16_t expected_stage)
{
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	initialize_capture_context(&test);
	test.capture_status = capture_status;
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_CAPTURE_ONCE;
	command.sequence = 29u;
	command.payload_length = 8u;
	command.capture.search_stop = 2047u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.capture_calls == 1u);
	CHECK(test.wire[5] == PL_FFT_LAB_ERROR);
	CHECK((int32_t)get_u32_le(&test.wire[16]) == capture_status);
	CHECK(get_u16_le(&test.wire[20]) == expected_stage);
	CHECK(test.wire_length == 28u);
}

static void test_invalid_config_is_rejected_before_hardware(void)
{
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	initialize_capture_context(&test);
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_CAPTURE_ONCE;
	command.sequence = 31u;
	command.payload_length = 8u;
	command.capture.search_start = 100u;
	command.capture.search_stop = 99u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.capture_calls == 0u);
	CHECK(test.wire[5] == PL_FFT_LAB_ERROR);
	CHECK((int32_t)get_u32_le(&test.wire[16]) == PL_FFT_ERR_CONFIG);
	CHECK(get_u16_le(&test.wire[20]) ==
	      PL_FFT_LAB_STAGE_CONFIG);
}

static void test_fatal_result_emits_error_not_spectrum(void)
{
	struct test_context test;
	struct pl_fft_lab_service service;
	struct pl_fft_lab_command command;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	initialize_capture_context(&test);
	test.capture_result.hardware_flags = 1u << 2;
	service = make_service(&test, spectrum);
	memset(&command, 0, sizeof(command));
	command.type = PL_FFT_LAB_CAPTURE_ONCE;
	command.sequence = 33u;
	command.payload_length = 8u;
	command.capture.search_stop = 2047u;

	CHECK(pl_fft_lab_service_command(&service, &command) ==
	      PL_FFT_LAB_OK);
	CHECK(test.capture_calls == 1u);
	CHECK(test.wire[5] == PL_FFT_LAB_ERROR);
	CHECK((int32_t)get_u32_le(&test.wire[16]) ==
	      PL_FFT_ERR_HARDWARE);
	CHECK(get_u16_le(&test.wire[20]) ==
	      PL_FFT_LAB_STAGE_CAPTURE);
	CHECK(test.wire_length == 28u);
}

int main(void)
{
	test_get_info_matches_exact_python_vector();
	test_rf_readback_failure_returns_config_error();
	test_capture_forwards_config_and_streams_exact_metadata();
	expect_capture_error(PL_FFT_ERR_NOT_READY,
			     PL_FFT_LAB_STAGE_BUSY);
	expect_capture_error(PL_FFT_ERR_HARDWARE,
			     PL_FFT_LAB_STAGE_CAPTURE);
	test_invalid_config_is_rejected_before_hardware();
	test_fatal_result_emits_error_not_spectrum();

	if (failures != 0) {
		printf("FAIL: pl_fft_lab_service failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_lab_service\n");
	return 0;
}
