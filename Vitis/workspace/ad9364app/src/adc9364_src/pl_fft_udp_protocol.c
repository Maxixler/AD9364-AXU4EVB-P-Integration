#include <stddef.h>

#include "pl_fft_udp_protocol.h"

_Static_assert(PL_FFT_SPECTRUM_WORDS == PL_FFT_UDP_FFT_SIZE,
	       "UDP FFT size must match PL spectrum size");

static void put_u16_be(uint8_t *dst, uint16_t value)
{
	dst[0] = (uint8_t)(value >> 8u);
	dst[1] = (uint8_t)value;
}

static void put_u32_be(uint8_t *dst, uint32_t value)
{
	dst[0] = (uint8_t)(value >> 24u);
	dst[1] = (uint8_t)(value >> 16u);
	dst[2] = (uint8_t)(value >> 8u);
	dst[3] = (uint8_t)value;
}

static void put_u64_be(uint8_t *dst, uint64_t value)
{
	uint32_t index;

	for (index = 0u; index < 8u; index++)
		dst[index] = (uint8_t)(value >> (56u - index * 8u));
}

int32_t pl_fft_udp_chunk_bounds(uint16_t chunk_index,
				 struct pl_fft_udp_chunk_view *view)
{
	uint16_t first_bin;
	uint16_t remaining;

	if (view == NULL || chunk_index >= PL_FFT_UDP_CHUNK_COUNT)
		return PL_FFT_UDP_ERR_ARGUMENT;

	first_bin = (uint16_t)(chunk_index * PL_FFT_UDP_BINS_PER_CHUNK);
	remaining = (uint16_t)(PL_FFT_UDP_FFT_SIZE - first_bin);
	view->first_bin = first_bin;
	view->bin_count = remaining > PL_FFT_UDP_BINS_PER_CHUNK ?
		PL_FFT_UDP_BINS_PER_CHUNK : remaining;
	return PL_FFT_UDP_OK;
}

int32_t pl_fft_udp_encode_header(uint8_t out[PL_FFT_UDP_HEADER_BYTES],
				 const struct pl_fft_udp_metadata *metadata,
				 uint16_t chunk_index)
{
	struct pl_fft_udp_chunk_view view;

	if (out == NULL || metadata == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	if (pl_fft_udp_chunk_bounds(chunk_index, &view) != PL_FFT_UDP_OK)
		return PL_FFT_UDP_ERR_ARGUMENT;

	put_u32_be(&out[0], PL_FFT_UDP_MAGIC);
	out[4] = PL_FFT_UDP_VERSION;
	out[5] = PL_FFT_UDP_PACKET_TYPE_FFT;
	put_u16_be(&out[6], PL_FFT_UDP_HEADER_BYTES);
	put_u32_be(&out[8], metadata->frame_id);
	put_u16_be(&out[12], chunk_index);
	put_u16_be(&out[14], PL_FFT_UDP_CHUNK_COUNT);
	put_u16_be(&out[16], view.first_bin);
	put_u16_be(&out[18], view.bin_count);
	put_u16_be(&out[20], PL_FFT_UDP_FFT_SIZE);
	put_u16_be(&out[22], metadata->hardware_flags);
	put_u64_be(&out[24], metadata->lo_hz);
	put_u32_be(&out[32], metadata->sample_rate_hz);
	put_u32_be(&out[36], metadata->bandwidth_hz);
	put_u16_be(&out[40], (uint16_t)metadata->gain_db);
	put_u16_be(&out[42], metadata->peak_bin);
	put_u64_be(&out[44], metadata->peak_power);
	put_u32_be(&out[52], metadata->frame_crc32);
	put_u16_be(&out[56], (uint16_t)metadata->peak_re);
	put_u16_be(&out[58], (uint16_t)metadata->peak_im);
	put_u16_be(&out[60], metadata->reset_epoch);
	out[62] = metadata->rf_state;
	out[63] = metadata->active_bank;
	return PL_FFT_UDP_OK;
}
