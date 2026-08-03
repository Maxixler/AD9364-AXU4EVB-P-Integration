#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pl_fft_udp_service.h"

struct fixture {
	struct pl_fft_udp_service service;
	struct pl_fft_result capture_result;
	struct pl_fft_udp_rf_snapshot rf;
	uint64_t spectrum[PL_FFT_UDP_FFT_SIZE];
	uint32_t capture_calls;
	uint32_t rf_reads;
	uint32_t sent_datagrams;
	uint32_t delay_calls;
	uint32_t last_delay_ms;
	uint32_t max_chunk_bytes;
	uint32_t stop_after_frames;
	uint16_t next_chunk;
	int32_t capture_status;
	int32_t rf_status;
	int32_t send_status;
	uint32_t fail_on_datagram;
	uint8_t last_header[PL_FFT_UDP_HEADER_BYTES];
};

static int failures;

#define CHECK(condition) do { \
	if (!(condition)) { \
		printf("FAIL line=%d condition=%s\n", __LINE__, #condition); \
		failures++; \
		return; \
	} \
} while (0)

static uint16_t get_u16_be(const uint8_t *value)
{
	return (uint16_t)(((uint16_t)value[0] << 8) | value[1]);
}

static uint32_t get_u32_be(const uint8_t *value)
{
	return ((uint32_t)value[0] << 24) |
	       ((uint32_t)value[1] << 16) |
	       ((uint32_t)value[2] << 8) |
	       (uint32_t)value[3];
}

static uint64_t get_u64_be(const uint8_t *value)
{
	return ((uint64_t)get_u32_be(value) << 32) |
	       get_u32_be(&value[4]);
}

static int32_t test_capture(void *context, struct pl_fft_result *result,
			    uint64_t spectrum[PL_FFT_UDP_FFT_SIZE])
{
	struct fixture *test = context;
	uint32_t index;

	test->capture_calls++;
	if (test->capture_status != PL_FFT_UDP_OK)
		return test->capture_status;
	*result = test->capture_result;
	for (index = 0u; index < PL_FFT_UDP_FFT_SIZE; index++)
		spectrum[index] = 0x0102030405060000ull + index;
	return PL_FFT_UDP_OK;
}

static int32_t test_read_rf(void *context,
			    struct pl_fft_udp_rf_snapshot *snapshot)
{
	struct fixture *test = context;

	test->rf_reads++;
	if (test->rf_status != PL_FFT_UDP_OK)
		return test->rf_status;
	*snapshot = test->rf;
	return PL_FFT_UDP_OK;
}

static int32_t test_send_datagram(void *context, const uint8_t *header,
				  uint32_t header_bytes,
				  const uint8_t *payload,
				  uint32_t payload_bytes)
{
	struct fixture *test = context;
	uint32_t expected_bytes;

	if (test->fail_on_datagram != 0u &&
	    test->sent_datagrams + 1u == test->fail_on_datagram)
		return test->send_status;
	if (header == NULL || payload == NULL ||
	    header_bytes != PL_FFT_UDP_HEADER_BYTES ||
	    get_u16_be(&header[12]) != test->next_chunk ||
	    get_u32_be(&header[8]) != test->capture_result.frame_id ||
	    get_u64_be(&header[24]) != test->rf.lo_hz ||
	    get_u32_be(&header[32]) != test->rf.sample_rate_hz ||
	    get_u32_be(&header[36]) != test->rf.bandwidth_hz ||
	    (int16_t)get_u16_be(&header[40]) != test->rf.gain_db ||
	    header[62] != test->rf.rf_state) {
		failures++;
		return -99;
	}
	expected_bytes = test->next_chunk + 1u == PL_FFT_UDP_CHUNK_COUNT ?
		112u * 8u : PL_FFT_UDP_BINS_PER_CHUNK * 8u;
	if (payload_bytes != expected_bytes || payload_bytes > 1472u ||
	    ((const uint64_t *)payload)[0] != 0x0102030405060000ull +
	    (uint32_t)test->next_chunk * PL_FFT_UDP_BINS_PER_CHUNK) {
		failures++;
		return -99;
	}
	memcpy(test->last_header, header, sizeof(test->last_header));
	if (payload_bytes > test->max_chunk_bytes)
		test->max_chunk_bytes = payload_bytes;
	test->sent_datagrams++;
	test->next_chunk++;
	if (test->next_chunk == PL_FFT_UDP_CHUNK_COUNT)
		test->next_chunk = 0u;
	return PL_FFT_UDP_OK;
}

static void test_delay_ms(void *context, uint32_t delay_ms)
{
	struct fixture *test = context;

	test->delay_calls++;
	test->last_delay_ms = delay_ms;
}

static bool test_should_stop(void *context)
{
	struct fixture *test = context;

	return test->service.completed_frames >= test->stop_after_frames;
}

static struct fixture fixture_make(void)
{
	struct fixture test;

	memset(&test, 0, sizeof(test));
	test.capture_status = PL_FFT_UDP_OK;
	test.rf_status = PL_FFT_UDP_OK;
	test.send_status = -77;
	test.capture_result.frame_id = 0x01020304u;
	test.capture_result.hardware_flags = 0x1122u;
	test.capture_result.peak_bin = 20u;
	test.capture_result.peak_power = 0x0102030405060708ull;
	test.capture_result.frame_crc32 = 0xaabbccddu;
	test.capture_result.peak_re = -123;
	test.capture_result.peak_im = 456;
	test.capture_result.reset_epoch = 7u;
	test.capture_result.rf_state = 3u;
	test.capture_result.active_bank = 1u;
	test.rf.lo_hz = 2400000000ull;
	test.rf.sample_rate_hz = 30720000u;
	test.rf.bandwidth_hz = 10000000u;
	test.rf.gain_db = 50;
	test.rf.rf_state = 2u;
	test.service.context = NULL;
	test.service.capture = test_capture;
	test.service.read_rf = test_read_rf;
	test.service.send_datagram = test_send_datagram;
	test.service.delay_ms = test_delay_ms;
	test.service.should_stop = test_should_stop;
	test.service.spectrum = test.spectrum;
	return test;
}

static void test_continuous_service_passes_frame_150(void)
{
	struct fixture test = fixture_make();

	test.service.context = &test;
	test.service.spectrum = test.spectrum;
	test.stop_after_frames = 151u;
	CHECK(pl_fft_udp_service_run(&test.service) == PL_FFT_UDP_STOPPED);
	CHECK(test.capture_calls == 151u);
	CHECK(test.rf_reads == 151u);
	CHECK(test.sent_datagrams == 151u * 12u);
	CHECK(test.delay_calls == 150u);
	CHECK(test.last_delay_ms == 250u);
	CHECK(test.max_chunk_bytes <= 1472u);
	CHECK(test.service.completed_frames == 151u);
	CHECK(get_u16_be(&test.last_header[12]) == 11u);
}

static void test_send_failure_stops_without_completing_frame(void)
{
	struct fixture test = fixture_make();

	test.service.context = &test;
	test.service.spectrum = test.spectrum;
	test.fail_on_datagram = 5u;
	CHECK(pl_fft_udp_service_run(&test.service) == test.send_status);
	CHECK(test.capture_calls == 1u);
	CHECK(test.rf_reads == 1u);
	CHECK(test.sent_datagrams == 4u);
	CHECK(test.service.completed_frames == 0u);
	CHECK(test.delay_calls == 0u);
}

static void test_invalid_service_is_rejected(void)
{
	struct fixture test = fixture_make();

	test.service.context = &test;
	test.service.spectrum = test.spectrum;
	CHECK(pl_fft_udp_service_send_frame(NULL) == PL_FFT_UDP_ERR_ARGUMENT);
	CHECK(pl_fft_udp_service_run(NULL) == PL_FFT_UDP_ERR_ARGUMENT);
	test.service.delay_ms = NULL;
	CHECK(pl_fft_udp_service_run(&test.service) == PL_FFT_UDP_ERR_ARGUMENT);
}

int main(void)
{
	test_continuous_service_passes_frame_150();
	test_send_failure_stops_without_completing_frame();
	test_invalid_service_is_rejected();
	if (failures != 0) {
		printf("FAIL: pl_fft_udp_service failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_udp_service 151 frames, 1812 datagrams\n");
	return 0;
}
