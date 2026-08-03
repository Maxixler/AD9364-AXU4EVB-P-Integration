#ifndef PL_FFT_UDP_PROTOCOL_H
#define PL_FFT_UDP_PROTOCOL_H

#include <stdint.h>

#include "pl_fft_control.h"

#define PL_FFT_UDP_MAGIC 0x41464654u
#define PL_FFT_UDP_VERSION 1u
#define PL_FFT_UDP_PACKET_TYPE_FFT 1u
#define PL_FFT_UDP_HEADER_BYTES 64u
#define PL_FFT_UDP_FFT_SIZE 2048u
#define PL_FFT_UDP_BINS_PER_CHUNK 176u
#define PL_FFT_UDP_CHUNK_COUNT 12u

#define PL_FFT_UDP_OK 0
#define PL_FFT_UDP_ERR_ARGUMENT (-1)

struct pl_fft_udp_chunk_view {
	uint16_t first_bin;
	uint16_t bin_count;
};

struct pl_fft_udp_metadata {
	uint32_t frame_id;
	uint16_t hardware_flags;
	uint64_t lo_hz;
	uint32_t sample_rate_hz;
	uint32_t bandwidth_hz;
	int16_t gain_db;
	uint16_t peak_bin;
	uint64_t peak_power;
	uint32_t frame_crc32;
	int16_t peak_re;
	int16_t peak_im;
	uint16_t reset_epoch;
	uint8_t rf_state;
	uint8_t active_bank;
};

int32_t pl_fft_udp_chunk_bounds(uint16_t chunk_index,
				 struct pl_fft_udp_chunk_view *view);
int32_t pl_fft_udp_encode_header(uint8_t out[PL_FFT_UDP_HEADER_BYTES],
				 const struct pl_fft_udp_metadata *metadata,
				 uint16_t chunk_index);

#endif
