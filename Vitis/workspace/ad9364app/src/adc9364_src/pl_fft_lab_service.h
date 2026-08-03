#ifndef PL_FFT_LAB_SERVICE_H
#define PL_FFT_LAB_SERVICE_H

#include <stdint.h>

#include "pl_fft_control.h"
#include "pl_fft_lab_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PL_FFT_LAB_STAGE_PARSE 1u
#define PL_FFT_LAB_STAGE_CONFIG 2u
#define PL_FFT_LAB_STAGE_BUSY 3u
#define PL_FFT_LAB_STAGE_CAPTURE 4u
#define PL_FFT_LAB_STAGE_UART 5u

struct pl_fft_lab_rf_snapshot {
	uint32_t sample_rate_hz;
	uint32_t rx_bandwidth_hz;
	uint64_t lo_hz;
	int16_t gain_db;
	uint8_t gain_mode;
};

struct pl_fft_lab_service {
	struct pl_fft_device *fft;
	struct pl_fft_lab_writer writer;
	void *rf_context;
	int32_t (*read_rf)(
		void *context, struct pl_fft_lab_rf_snapshot *snapshot);
	uint64_t *spectrum;
};

int32_t pl_fft_lab_service_command(
	struct pl_fft_lab_service *service,
	const struct pl_fft_lab_command *command);

#ifdef __cplusplus
}
#endif

#endif
