#include "monopulse_spectrum.h"

#include <errno.h>
#include <limits.h>
#include <stddef.h>

static uint64_t monopulse_saturating_add(uint64_t accumulator, uint64_t value)
{
	if (UINT64_MAX - accumulator < value)
		return UINT64_MAX;

	return accumulator + value;
}

static int32_t monopulse_validate_spectra(const struct monopulse_spectra *spectra)
{
	uint32_t state;

	if (spectra == NULL)
		return -EINVAL;

	for (state = 0U; state < MONOPULSE_STATE_COUNT; ++state) {
		if (spectra->state[state] == NULL)
			return -EINVAL;
	}

	return 0;
}

static int32_t monopulse_validate_config(
	const struct monopulse_spectrum_config *cfg)
{
	if (cfg == NULL || cfg->fft_size != MONOPULSE_FFT_SIZE ||
		cfg->search_bin_start > cfg->search_bin_stop ||
		cfg->search_bin_stop >= MONOPULSE_FFT_SIZE ||
		cfg->band_bin_start > cfg->band_bin_stop ||
		cfg->band_bin_stop >= MONOPULSE_FFT_SIZE ||
		cfg->dc_guard_bins >= MONOPULSE_FFT_SIZE ||
		cfg->cw_half_width >= MONOPULSE_FFT_SIZE)
		return -EINVAL;

	return 0;
}

static void monopulse_set_power(struct monopulse_power_set *powers,
	uint32_t state, uint64_t value)
{
	switch (state) {
	case MONOPULSE_AZ_PLUS:
		powers->az_plus = value;
		break;
	case MONOPULSE_AZ_MINUS:
		powers->az_minus = value;
		break;
	case MONOPULSE_EL_PLUS:
		powers->el_plus = value;
		break;
	case MONOPULSE_EL_MINUS:
		powers->el_minus = value;
		break;
	default:
		break;
	}
}

static uint64_t monopulse_sum_state_interval(const uint64_t *spectrum,
	uint32_t start_bin, uint32_t stop_bin)
{
	uint32_t bin;
	uint64_t sum = 0U;

	for (bin = start_bin; bin <= stop_bin; ++bin)
		sum = monopulse_saturating_add(sum, spectrum[bin]);

	return sum;
}

int32_t monopulse_find_common_peak(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t *peak_bin,
	uint64_t *peak_power)
{
	uint32_t bin;
	uint32_t state;
	uint32_t first_bin;
	uint64_t selected_power = 0U;

	if (monopulse_validate_spectra(spectra) != 0 ||
		monopulse_validate_config(cfg) != 0 || peak_bin == NULL ||
		peak_power == NULL)
		return -EINVAL;

	first_bin = cfg->search_bin_start;
	if (first_bin < cfg->dc_guard_bins)
		first_bin = cfg->dc_guard_bins;
	if (first_bin > cfg->search_bin_stop)
		return -EINVAL;

	for (bin = first_bin; bin <= cfg->search_bin_stop; ++bin) {
		uint64_t common_power = 0U;

		for (state = 0U; state < MONOPULSE_STATE_COUNT; ++state) {
			common_power = monopulse_saturating_add(common_power,
				spectra->state[state][bin]);
		}

		if (bin == first_bin || common_power > selected_power) {
			*peak_bin = bin;
			selected_power = common_power;
		}
	}

	*peak_power = selected_power;
	return 0;
}

int32_t monopulse_integrate_cw(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg, uint32_t peak_bin,
	struct monopulse_power_set *powers)
{
	uint32_t state;
	uint32_t start_bin;
	uint32_t stop_bin;

	if (monopulse_validate_spectra(spectra) != 0 ||
		monopulse_validate_config(cfg) != 0 || powers == NULL ||
		peak_bin < cfg->cw_half_width ||
		peak_bin >= MONOPULSE_FFT_SIZE ||
		cfg->cw_half_width > MONOPULSE_FFT_SIZE - 1U - peak_bin)
		return -EINVAL;

	start_bin = peak_bin - cfg->cw_half_width;
	stop_bin = peak_bin + cfg->cw_half_width;
	for (state = 0U; state < MONOPULSE_STATE_COUNT; ++state)
		monopulse_set_power(powers, state,
			monopulse_sum_state_interval(spectra->state[state], start_bin,
				stop_bin));

	return 0;
}

int32_t monopulse_integrate_band(const struct monopulse_spectra *spectra,
	const struct monopulse_spectrum_config *cfg,
	struct monopulse_power_set *powers)
{
	uint32_t state;

	if (monopulse_validate_spectra(spectra) != 0 ||
		monopulse_validate_config(cfg) != 0 || powers == NULL)
		return -EINVAL;

	for (state = 0U; state < MONOPULSE_STATE_COUNT; ++state)
		monopulse_set_power(powers, state,
			monopulse_sum_state_interval(spectra->state[state],
				cfg->band_bin_start, cfg->band_bin_stop));

	return 0;
}
