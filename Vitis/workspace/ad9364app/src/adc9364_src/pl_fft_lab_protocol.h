#ifndef PL_FFT_LAB_PROTOCOL_H
#define PL_FFT_LAB_PROTOCOL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PL_FFT_LAB_PROTOCOL_VERSION 2u
#define PL_FFT_LAB_HEADER_SIZE 16u
#define PL_FFT_LAB_CRC_SIZE 4u
#define PL_FFT_LAB_COMMAND_PAYLOAD_MAX 8u
#define PL_FFT_LAB_MAX_PAYLOAD 16448u
#define PL_FFT_LAB_MAX_WIRE_SIZE \
	(PL_FFT_LAB_HEADER_SIZE + PL_FFT_LAB_MAX_PAYLOAD + \
	 PL_FFT_LAB_CRC_SIZE)
#define PL_FFT_LAB_RELEASE_ID_SIZE 32u
#define PL_FFT_LAB_SPECTRUM_WORDS 2048u

#define PL_FFT_LAB_OK 0
#define PL_FFT_LAB_ERR_ARGUMENT (-1)
#define PL_FFT_LAB_ERR_PROTOCOL (-2)
#define PL_FFT_LAB_ERR_WRITER (-3)

enum pl_fft_lab_message_type {
	PL_FFT_LAB_GET_INFO = 0x01,
	PL_FFT_LAB_INFO = 0x02,
	PL_FFT_LAB_CAPTURE_ONCE = 0x03,
	PL_FFT_LAB_SPECTRUM = 0x04,
	PL_FFT_LAB_ERROR = 0x7e
};

enum pl_fft_lab_parser_event {
	PL_FFT_LAB_COMMAND_REJECTED = -1,
	PL_FFT_LAB_COMMAND_NONE = 0,
	PL_FFT_LAB_COMMAND_READY = 1
};

enum pl_fft_lab_gain_mode {
	PL_FFT_LAB_GAIN_MODE_MANUAL = 0u
};

struct pl_fft_lab_capture {
	uint16_t search_start;
	uint16_t search_stop;
	uint16_t dc_guard;
	uint8_t rf_state;
};

struct pl_fft_lab_command {
	uint8_t type;
	uint32_t sequence;
	uint32_t payload_length;
	struct pl_fft_lab_capture capture;
};

struct pl_fft_lab_parser {
	uint8_t bytes[PL_FFT_LAB_HEADER_SIZE +
		      PL_FFT_LAB_COMMAND_PAYLOAD_MAX +
		      PL_FFT_LAB_CRC_SIZE];
	uint32_t used;
	uint32_t expected;
};

typedef int32_t (*pl_fft_lab_write_fn)(
	void *context, const uint8_t *data, uint32_t length,
	uint32_t *written);

struct pl_fft_lab_writer {
	void *context;
	pl_fft_lab_write_fn write;
};

struct pl_fft_lab_info {
	uint16_t board_code;
	uint16_t rf_device_code;
	uint32_t firmware_version;
	uint32_t feature_bits;
	uint16_t fft_size;
	uint8_t spectrum_word_bytes;
	uint8_t rf_state_count;
	uint32_t sample_rate_hz;
	uint32_t rx_bandwidth_hz;
	uint64_t lo_hz;
	int16_t gain_db;
	uint8_t gain_mode;
	uint8_t release_id[PL_FFT_LAB_RELEASE_ID_SIZE];
};

struct pl_fft_lab_spectrum {
	uint32_t frame_id;
	uint16_t sample_count;
	uint16_t fft_size;
	uint32_t sample_rate_hz;
	uint32_t rx_bandwidth_hz;
	uint64_t lo_hz;
	uint32_t frame_crc32;
	uint32_t skipped_sample_count;
	uint64_t peak_power;
	uint16_t peak_bin;
	int16_t peak_re;
	int16_t peak_im;
	uint16_t reset_epoch;
	uint8_t rf_state;
	uint8_t active_bank;
	uint16_t hardware_flags;
	int16_t gain_db;
	uint8_t gain_mode;
};

void pl_fft_lab_parser_init(struct pl_fft_lab_parser *parser);

int32_t pl_fft_lab_parser_push(
	struct pl_fft_lab_parser *parser, uint8_t byte,
	struct pl_fft_lab_command *command);

uint32_t pl_fft_lab_crc32_update(
	uint32_t crc, const uint8_t *data, uint32_t length);

int32_t pl_fft_lab_write_info(
	const struct pl_fft_lab_writer *writer, uint32_t sequence,
	const struct pl_fft_lab_info *info);

int32_t pl_fft_lab_write_spectrum(
	const struct pl_fft_lab_writer *writer, uint32_t sequence,
	const struct pl_fft_lab_spectrum *spectrum,
	const uint64_t bins[PL_FFT_LAB_SPECTRUM_WORDS]);

int32_t pl_fft_lab_write_error(
	const struct pl_fft_lab_writer *writer, uint32_t sequence,
	int32_t error_code, uint16_t stage);

#ifdef __cplusplus
}
#endif

#endif
