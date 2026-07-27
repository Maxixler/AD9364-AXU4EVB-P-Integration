#include "pl_fft_monitor.h"

#include <stddef.h>

int pl_fft_monitor_run(struct pl_fft_monitor *monitor,
		       uint32_t frame_count, uint32_t interval_ms,
		       uint64_t spectrum[PL_FFT_SPECTRUM_WORDS],
		       uint32_t *completed_frames)
{
	struct pl_fft_result result;
	uint32_t sequence;
	int status;

	if (monitor == NULL || monitor->device == NULL ||
	    monitor->delay_ms == NULL || monitor->report_frame == NULL ||
	    spectrum == NULL || completed_frames == NULL)
		return PL_FFT_ERR_ARGUMENT;
	if (frame_count == 0u || interval_ms == 0u)
		return PL_FFT_ERR_CONFIG;

	*completed_frames = 0u;
	for (sequence = 1u; sequence <= frame_count; sequence++) {
		status = pl_fft_capture_once(monitor->device, 0u, 2047u,
					     0u, 0u, &result, spectrum);
		if (status != PL_FFT_OK)
			return status;
		monitor->report_frame(monitor->callback_context, sequence,
				      frame_count, &result);
		*completed_frames = sequence;
		if (sequence < frame_count)
			monitor->delay_ms(monitor->callback_context, interval_ms);
	}
	return PL_FFT_OK;
}
