#include "pl_fft_lab_protocol.h"

#include <stddef.h>
#include <string.h>

#define PL_FFT_LAB_INFO_PAYLOAD_SIZE 68u
#define PL_FFT_LAB_SPECTRUM_PREFIX_SIZE 56u
#define PL_FFT_LAB_ERROR_PAYLOAD_SIZE 8u
#define PL_FFT_LAB_FEATURE_MASK 0x0000000fu
#define PL_FFT_LAB_HARDWARE_FLAG_MASK 0x003fu

static const uint8_t request_magic[4] = {'M', 'P', 'L', 'Q'};
static const uint8_t response_magic[4] = {'M', 'P', 'L', 'R'};

static void put_u16_le(uint8_t out[2], uint16_t value)
{
	out[0] = (uint8_t)value;
	out[1] = (uint8_t)(value >> 8);
}

static void put_u32_le(uint8_t out[4], uint32_t value)
{
	out[0] = (uint8_t)value;
	out[1] = (uint8_t)(value >> 8);
	out[2] = (uint8_t)(value >> 16);
	out[3] = (uint8_t)(value >> 24);
}

static void put_u64_le(uint8_t out[8], uint64_t value)
{
	put_u32_le(out, (uint32_t)value);
	put_u32_le(&out[4], (uint32_t)(value >> 32));
}

static uint32_t get_u32_le(const uint8_t in[4])
{
	return (uint32_t)in[0] |
	       ((uint32_t)in[1] << 8) |
	       ((uint32_t)in[2] << 16) |
	       ((uint32_t)in[3] << 24);
}

static uint16_t get_u16_le(const uint8_t in[2])
{
	return (uint16_t)((uint16_t)in[0] |
			  ((uint16_t)in[1] << 8));
}

static int32_t write_all(const struct pl_fft_lab_writer *writer,
			 const uint8_t *data, uint32_t length)
{
	uint32_t offset = 0u;

	if (writer == NULL || writer->write == NULL ||
	    (data == NULL && length != 0u))
		return PL_FFT_LAB_ERR_ARGUMENT;
	while (offset < length) {
		uint32_t written = 0u;
		int32_t status = writer->write(
			writer->context, &data[offset], length - offset,
			&written);

		if (status != PL_FFT_LAB_OK)
			return status;
		if (written == 0u || written > length - offset)
			return PL_FFT_LAB_ERR_WRITER;
		offset += written;
	}
	return PL_FFT_LAB_OK;
}

static void encode_header(uint8_t header[PL_FFT_LAB_HEADER_SIZE],
			  uint8_t type, uint32_t payload_length,
			  uint32_t sequence)
{
	memcpy(header, response_magic, sizeof(response_magic));
	header[4] = PL_FFT_LAB_PROTOCOL_VERSION;
	header[5] = type;
	put_u16_le(&header[6], 0u);
	put_u32_le(&header[8], payload_length);
	put_u32_le(&header[12], sequence);
}

uint32_t pl_fft_lab_crc32_update(uint32_t crc, const uint8_t *data,
				 uint32_t length)
{
	uint32_t index;

	if (data == NULL)
		return crc;
	for (index = 0u; index < length; index++) {
		uint32_t bit;

		crc ^= data[index];
		for (bit = 0u; bit < 8u; bit++)
			crc = (crc >> 1) ^
			      (0xedb88320u & (0u - (crc & 1u)));
	}
	return crc;
}

void pl_fft_lab_parser_init(struct pl_fft_lab_parser *parser)
{
	if (parser != NULL)
		memset(parser, 0, sizeof(*parser));
}

static void parser_reset(struct pl_fft_lab_parser *parser)
{
	parser->used = 0u;
	parser->expected = 0u;
}

int32_t pl_fft_lab_parser_push(struct pl_fft_lab_parser *parser,
			       uint8_t byte,
			       struct pl_fft_lab_command *command)
{
	uint32_t payload_length;
	uint32_t received_crc;
	uint32_t calculated_crc;

	if (parser == NULL || command == NULL)
		return PL_FFT_LAB_COMMAND_REJECTED;
	if (parser->used == 0u && byte != request_magic[0])
		return PL_FFT_LAB_COMMAND_NONE;
	if (parser->used >= sizeof(parser->bytes)) {
		parser_reset(parser);
		return PL_FFT_LAB_COMMAND_REJECTED;
	}
	parser->bytes[parser->used++] = byte;
	if (parser->used <= sizeof(request_magic) &&
	    parser->bytes[parser->used - 1u] !=
		    request_magic[parser->used - 1u]) {
		parser_reset(parser);
		if (byte == request_magic[0]) {
			parser->bytes[0] = byte;
			parser->used = 1u;
		}
		return PL_FFT_LAB_COMMAND_NONE;
	}
	if (parser->used < PL_FFT_LAB_HEADER_SIZE)
		return PL_FFT_LAB_COMMAND_NONE;

	if (parser->used == PL_FFT_LAB_HEADER_SIZE) {
		payload_length = get_u32_le(&parser->bytes[8]);
		if (parser->bytes[4] != PL_FFT_LAB_PROTOCOL_VERSION ||
		    parser->bytes[6] != 0u || parser->bytes[7] != 0u ||
		    payload_length > PL_FFT_LAB_COMMAND_PAYLOAD_MAX) {
			parser_reset(parser);
			return PL_FFT_LAB_COMMAND_REJECTED;
		}
		if ((parser->bytes[5] == PL_FFT_LAB_GET_INFO &&
		     payload_length != 0u) ||
		    (parser->bytes[5] == PL_FFT_LAB_CAPTURE_ONCE &&
		     payload_length != 8u) ||
		    (parser->bytes[5] != PL_FFT_LAB_GET_INFO &&
		     parser->bytes[5] != PL_FFT_LAB_CAPTURE_ONCE)) {
			parser_reset(parser);
			return PL_FFT_LAB_COMMAND_REJECTED;
		}
		parser->expected = PL_FFT_LAB_HEADER_SIZE +
				   payload_length + PL_FFT_LAB_CRC_SIZE;
	}
	if (parser->used < parser->expected)
		return PL_FFT_LAB_COMMAND_NONE;

	received_crc = get_u32_le(&parser->bytes[parser->expected - 4u]);
	calculated_crc = pl_fft_lab_crc32_update(
		0xffffffffu, parser->bytes, parser->expected - 4u) ^
		0xffffffffu;
	if (received_crc != calculated_crc) {
		parser_reset(parser);
		return PL_FFT_LAB_COMMAND_REJECTED;
	}

	memset(command, 0, sizeof(*command));
	command->type = parser->bytes[5];
	command->payload_length = get_u32_le(&parser->bytes[8]);
	command->sequence = get_u32_le(&parser->bytes[12]);
	if (command->type == PL_FFT_LAB_CAPTURE_ONCE) {
		const uint8_t *payload =
			&parser->bytes[PL_FFT_LAB_HEADER_SIZE];

		if (payload[7] != 0u) {
			parser_reset(parser);
			return PL_FFT_LAB_COMMAND_REJECTED;
		}
		command->capture.search_start = get_u16_le(&payload[0]);
		command->capture.search_stop = get_u16_le(&payload[2]);
		command->capture.dc_guard = get_u16_le(&payload[4]);
		command->capture.rf_state = payload[6];
	}
	parser_reset(parser);
	return PL_FFT_LAB_COMMAND_READY;
}

int32_t pl_fft_lab_write_info(const struct pl_fft_lab_writer *writer,
			       uint32_t sequence,
			       const struct pl_fft_lab_info *info)
{
	uint8_t header[PL_FFT_LAB_HEADER_SIZE];
	uint8_t payload[PL_FFT_LAB_INFO_PAYLOAD_SIZE];
	uint8_t crc_bytes[PL_FFT_LAB_CRC_SIZE];
	uint32_t crc;
	int32_t status;

	if (info == NULL)
		return PL_FFT_LAB_ERR_ARGUMENT;
	if ((info->feature_bits & ~PL_FFT_LAB_FEATURE_MASK) != 0u ||
	    info->fft_size != PL_FFT_LAB_SPECTRUM_WORDS ||
	    info->spectrum_word_bytes != 8u ||
	    info->gain_mode != PL_FFT_LAB_GAIN_MODE_MANUAL ||
	    (info->rf_state_count != 1u &&
	     info->rf_state_count != 4u))
		return PL_FFT_LAB_ERR_ARGUMENT;
	memset(payload, 0, sizeof(payload));
	put_u16_le(&payload[0], info->board_code);
	put_u16_le(&payload[2], info->rf_device_code);
	put_u32_le(&payload[4], info->firmware_version);
	put_u32_le(&payload[8], info->feature_bits);
	put_u16_le(&payload[12], info->fft_size);
	payload[14] = info->spectrum_word_bytes;
	payload[15] = info->rf_state_count;
	put_u32_le(&payload[16], info->sample_rate_hz);
	put_u32_le(&payload[20], info->rx_bandwidth_hz);
	put_u64_le(&payload[24], info->lo_hz);
	put_u16_le(&payload[32], (uint16_t)info->gain_db);
	payload[34] = info->gain_mode;
	payload[35] = 0u;
	memcpy(&payload[36], info->release_id,
	       PL_FFT_LAB_RELEASE_ID_SIZE);
	encode_header(header, PL_FFT_LAB_INFO, sizeof(payload), sequence);
	crc = pl_fft_lab_crc32_update(
		0xffffffffu, header, sizeof(header));
	crc = pl_fft_lab_crc32_update(crc, payload, sizeof(payload));
	put_u32_le(crc_bytes, crc ^ 0xffffffffu);

	status = write_all(writer, header, sizeof(header));
	if (status == PL_FFT_LAB_OK)
		status = write_all(writer, payload, sizeof(payload));
	if (status == PL_FFT_LAB_OK)
		status = write_all(writer, crc_bytes, sizeof(crc_bytes));
	return status;
}

int32_t pl_fft_lab_write_error(const struct pl_fft_lab_writer *writer,
				uint32_t sequence, int32_t error_code,
				uint16_t stage)
{
	uint8_t header[PL_FFT_LAB_HEADER_SIZE];
	uint8_t payload[PL_FFT_LAB_ERROR_PAYLOAD_SIZE];
	uint8_t crc_bytes[PL_FFT_LAB_CRC_SIZE];
	uint32_t crc;
	int32_t status;

	if (stage < 1u || stage > 5u)
		return PL_FFT_LAB_ERR_ARGUMENT;
	put_u32_le(&payload[0], (uint32_t)error_code);
	put_u16_le(&payload[4], stage);
	put_u16_le(&payload[6], 0u);
	encode_header(header, PL_FFT_LAB_ERROR, sizeof(payload), sequence);
	crc = pl_fft_lab_crc32_update(
		0xffffffffu, header, sizeof(header));
	crc = pl_fft_lab_crc32_update(crc, payload, sizeof(payload));
	put_u32_le(crc_bytes, crc ^ 0xffffffffu);

	status = write_all(writer, header, sizeof(header));
	if (status == PL_FFT_LAB_OK)
		status = write_all(writer, payload, sizeof(payload));
	if (status == PL_FFT_LAB_OK)
		status = write_all(writer, crc_bytes, sizeof(crc_bytes));
	return status;
}

static void encode_spectrum_prefix(
	uint8_t payload[PL_FFT_LAB_SPECTRUM_PREFIX_SIZE],
	const struct pl_fft_lab_spectrum *spectrum)
{
	memset(payload, 0, PL_FFT_LAB_SPECTRUM_PREFIX_SIZE);
	put_u32_le(&payload[0], spectrum->frame_id);
	put_u16_le(&payload[4], spectrum->sample_count);
	put_u16_le(&payload[6], spectrum->fft_size);
	put_u32_le(&payload[8], spectrum->sample_rate_hz);
	put_u32_le(&payload[12], spectrum->rx_bandwidth_hz);
	put_u64_le(&payload[16], spectrum->lo_hz);
	put_u32_le(&payload[24], spectrum->frame_crc32);
	put_u32_le(&payload[28], spectrum->skipped_sample_count);
	put_u64_le(&payload[32], spectrum->peak_power);
	put_u16_le(&payload[40], spectrum->peak_bin);
	put_u16_le(&payload[42], (uint16_t)spectrum->peak_re);
	put_u16_le(&payload[44], (uint16_t)spectrum->peak_im);
	put_u16_le(&payload[46], spectrum->reset_epoch);
	payload[48] = spectrum->rf_state;
	payload[49] = spectrum->active_bank;
	put_u16_le(&payload[50], spectrum->hardware_flags);
	put_u16_le(&payload[52], (uint16_t)spectrum->gain_db);
	payload[54] = spectrum->gain_mode;
	payload[55] = 0u;
}

int32_t pl_fft_lab_write_spectrum(
	const struct pl_fft_lab_writer *writer, uint32_t sequence,
	const struct pl_fft_lab_spectrum *spectrum,
	const uint64_t bins[PL_FFT_LAB_SPECTRUM_WORDS])
{
	uint8_t header[PL_FFT_LAB_HEADER_SIZE];
	uint8_t payload[PL_FFT_LAB_SPECTRUM_PREFIX_SIZE];
	uint8_t word[8];
	uint8_t crc_bytes[PL_FFT_LAB_CRC_SIZE];
	uint32_t crc;
	uint32_t index;
	uint32_t payload_length =
		PL_FFT_LAB_SPECTRUM_PREFIX_SIZE +
		PL_FFT_LAB_SPECTRUM_WORDS * 8u;
	int32_t status;

	if (spectrum == NULL || bins == NULL)
		return PL_FFT_LAB_ERR_ARGUMENT;
	if (spectrum->sample_count != PL_FFT_LAB_SPECTRUM_WORDS ||
	    spectrum->fft_size != PL_FFT_LAB_SPECTRUM_WORDS ||
	    spectrum->peak_bin >= PL_FFT_LAB_SPECTRUM_WORDS ||
	    spectrum->rf_state > 7u || spectrum->active_bank > 1u ||
	    spectrum->gain_mode != PL_FFT_LAB_GAIN_MODE_MANUAL ||
	    (spectrum->hardware_flags &
	     ~PL_FFT_LAB_HARDWARE_FLAG_MASK) != 0u)
		return PL_FFT_LAB_ERR_ARGUMENT;

	encode_header(header, PL_FFT_LAB_SPECTRUM,
		      payload_length, sequence);
	encode_spectrum_prefix(payload, spectrum);
	crc = pl_fft_lab_crc32_update(
		0xffffffffu, header, sizeof(header));
	crc = pl_fft_lab_crc32_update(crc, payload, sizeof(payload));
	status = write_all(writer, header, sizeof(header));
	if (status != PL_FFT_LAB_OK)
		return status;
	status = write_all(writer, payload, sizeof(payload));
	if (status != PL_FFT_LAB_OK)
		return status;

	for (index = 0u; index < PL_FFT_LAB_SPECTRUM_WORDS; index++) {
		put_u64_le(word, bins[index]);
		crc = pl_fft_lab_crc32_update(crc, word, sizeof(word));
		status = write_all(writer, word, sizeof(word));
		if (status != PL_FFT_LAB_OK)
			return status;
	}
	put_u32_le(crc_bytes, crc ^ 0xffffffffu);
	return write_all(writer, crc_bytes, sizeof(crc_bytes));
}
