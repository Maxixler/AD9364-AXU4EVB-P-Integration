#ifndef MONOPULSE_SPECTRUM_H
#define MONOPULSE_SPECTRUM_H

#include <stdint.h>

#include "monopulse_math.h"
#include "monopulse_sequence.h"

#define MONOPULSE_FFT_SIZE 2048U

struct monopulse_spectra {
	const uint64_t *state[MONOPULSE_STATE_COUNT];
};

struct monopulse_spectrum_config {
	uint32_t fft_size;
	uint32_t search_bin_start;
	uint32_t search_bin_stop;
	uint32_t dc_guard_bins;
	uint32_t cw_half_width;
	uint32_t band_bin_start;
	uint32_t band_bin_stop;
};

int32_t monopulse_find_common_peak(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t *peak_bin,
	uint64_t *peak_power);
int32_t monopulse_integrate_cw(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t peak_bin,
	struct monopulse_power_set *powers);
int32_t monopulse_integrate_band(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg,
	struct monopulse_power_set *powers);

#endif
