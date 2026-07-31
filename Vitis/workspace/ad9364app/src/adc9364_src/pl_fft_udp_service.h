#ifndef PL_FFT_UDP_SERVICE_H
#define PL_FFT_UDP_SERVICE_H

#include <stdbool.h>
#include <stdint.h>

#include "pl_fft_udp_protocol.h"

#define PL_FFT_UDP_STOPPED (-2)

struct pl_fft_udp_rf_snapshot {
	uint64_t lo_hz;
	uint32_t sample_rate_hz;
	uint32_t bandwidth_hz;
	int16_t gain_db;
	uint8_t rf_state;
};

struct pl_fft_udp_service {
	void *context;
	int32_t (*capture)(void *context, struct pl_fft_result *result,
			   uint64_t spectrum[PL_FFT_UDP_FFT_SIZE]);
	int32_t (*read_rf)(void *context,
			   struct pl_fft_udp_rf_snapshot *snapshot);
	int32_t (*send_datagram)(void *context, const uint8_t *header,
				 uint32_t header_bytes, const uint8_t *payload,
				 uint32_t payload_bytes);
	void (*delay_ms)(void *context, uint32_t delay_ms);
	bool (*should_stop)(void *context);
	uint64_t *spectrum;
	uint32_t completed_frames;
};

int32_t pl_fft_udp_service_send_frame(struct pl_fft_udp_service *service);
int32_t pl_fft_udp_service_run(struct pl_fft_udp_service *service);

#endif
