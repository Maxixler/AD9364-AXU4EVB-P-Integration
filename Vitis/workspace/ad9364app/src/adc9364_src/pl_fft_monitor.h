#ifndef PL_FFT_MONITOR_H
#define PL_FFT_MONITOR_H

#include <stdint.h>

#include "pl_fft_control.h"

typedef void (*pl_fft_monitor_delay_fn)(void *context, uint32_t delay_ms);
typedef void (*pl_fft_monitor_report_fn)(void *context, uint32_t sequence,
					 uint32_t total,
					 const struct pl_fft_result *result);

struct pl_fft_monitor {
	struct pl_fft_device *device;
	void *callback_context;
	pl_fft_monitor_delay_fn delay_ms;
	pl_fft_monitor_report_fn report_frame;
};

int pl_fft_monitor_run(struct pl_fft_monitor *monitor,
		       uint32_t frame_count, uint32_t interval_ms,
		       uint64_t spectrum[PL_FFT_SPECTRUM_WORDS],
		       uint32_t *completed_frames);

#endif
