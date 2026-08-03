#include <stddef.h>

#include "pl_fft_udp_service.h"

static int32_t pl_fft_udp_service_validate(
	const struct pl_fft_udp_service *service)
{
	if (service == NULL || service->capture == NULL ||
	    service->read_rf == NULL || service->send_datagram == NULL ||
	    service->spectrum == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	return PL_FFT_UDP_OK;
}

int32_t pl_fft_udp_service_send_frame(struct pl_fft_udp_service *service)
{
	struct pl_fft_result result;
	struct pl_fft_udp_rf_snapshot rf;
	struct pl_fft_udp_metadata metadata;
	struct pl_fft_udp_chunk_view chunk;
	uint8_t header[PL_FFT_UDP_HEADER_BYTES];
	uint16_t chunk_index;
	int32_t status;

	status = pl_fft_udp_service_validate(service);
	if (status != PL_FFT_UDP_OK)
		return status;
	status = service->capture(service->context, &result, service->spectrum);
	if (status != PL_FFT_UDP_OK)
		return status;
	status = service->read_rf(service->context, &rf);
	if (status != PL_FFT_UDP_OK)
		return status;
	metadata.frame_id = result.frame_id;
	metadata.hardware_flags = result.hardware_flags;
	metadata.lo_hz = rf.lo_hz;
	metadata.sample_rate_hz = rf.sample_rate_hz;
	metadata.bandwidth_hz = rf.bandwidth_hz;
	metadata.gain_db = rf.gain_db;
	metadata.peak_bin = result.peak_bin;
	metadata.peak_power = result.peak_power;
	metadata.frame_crc32 = result.frame_crc32;
	metadata.peak_re = result.peak_re;
	metadata.peak_im = result.peak_im;
	metadata.reset_epoch = result.reset_epoch;
	metadata.rf_state = rf.rf_state;
	metadata.active_bank = result.active_bank;

	for (chunk_index = 0u; chunk_index < PL_FFT_UDP_CHUNK_COUNT;
	     chunk_index++) {
		status = pl_fft_udp_chunk_bounds(chunk_index, &chunk);
		if (status != PL_FFT_UDP_OK)
			return status;
		status = pl_fft_udp_encode_header(header, &metadata, chunk_index);
		if (status != PL_FFT_UDP_OK)
			return status;
		status = service->send_datagram(service->context, header,
						PL_FFT_UDP_HEADER_BYTES,
						(const uint8_t *)&service->spectrum[
							chunk.first_bin],
						(uint32_t)chunk.bin_count *
						sizeof(service->spectrum[0]));
		if (status != PL_FFT_UDP_OK)
			return status;
	}
	service->completed_frames++;
	return PL_FFT_UDP_OK;
}

int32_t pl_fft_udp_service_run(struct pl_fft_udp_service *service)
{
	int32_t status;

	if (pl_fft_udp_service_validate(service) != PL_FFT_UDP_OK ||
	    service->delay_ms == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	for (;;) {
		status = pl_fft_udp_service_send_frame(service);
		if (status != PL_FFT_UDP_OK)
			return status;
		if (service->should_stop != NULL &&
		    service->should_stop(service->context))
			return PL_FFT_UDP_STOPPED;
		service->delay_ms(service->context, 250u);
	}
}
