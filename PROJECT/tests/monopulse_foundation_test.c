#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

#include "monopulse_math.h"
#include "monopulse_sequence.h"
#include "monopulse_spectrum.h"

static struct monopulse_spectrum_config valid_spectrum_config(void)
{
	return (struct monopulse_spectrum_config){
		.fft_size = MONOPULSE_FFT_SIZE,
		.search_bin_start = 8U,
		.search_bin_stop = 1023U,
		.dc_guard_bins = 4U,
		.cw_half_width = 2U,
		.band_bin_start = 64U,
		.band_bin_stop = 511U
	};
}

static struct monopulse_spectra spectra_from_arrays(
	const uint64_t *az_plus, const uint64_t *az_minus,
	const uint64_t *el_plus, const uint64_t *el_minus)
{
	struct monopulse_spectra spectra = {
		.state = { az_plus, az_minus, el_plus, el_minus }
	};

	return spectra;
}

static void assert_powers(const struct monopulse_power_set *powers,
	uint64_t az_plus, uint64_t az_minus, uint64_t el_plus,
	uint64_t el_minus)
{
	assert(powers->az_plus == az_plus);
	assert(powers->az_minus == az_minus);
	assert(powers->el_plus == el_plus);
	assert(powers->el_minus == el_minus);
}

static void test_common_peak_and_cw_integration(void)
{
	static uint64_t az_plus[MONOPULSE_FFT_SIZE];
	static uint64_t az_minus[MONOPULSE_FFT_SIZE];
	static uint64_t el_plus[MONOPULSE_FFT_SIZE];
	static uint64_t el_minus[MONOPULSE_FFT_SIZE];
	struct monopulse_spectrum_config cfg = valid_spectrum_config();
	struct monopulse_spectra spectra = spectra_from_arrays(az_plus, az_minus,
		el_plus, el_minus);
	struct monopulse_power_set powers;
	uint32_t peak_bin;
	uint64_t peak_power;

	/* A large one-state DC spur must not participate in common-peak search. */
	cfg.search_bin_start = 0U;
	cfg.search_bin_stop = 101U;
	az_plus[3] = 1000U;

	/* Both totals are 100; the deterministic tie-break chooses bin 100. */
	az_plus[100] = 10U;
	az_minus[100] = 20U;
	el_plus[100] = 30U;
	el_minus[100] = 40U;
	az_plus[101] = 1U;
	az_minus[101] = 2U;
	el_plus[101] = 3U;
	el_minus[101] = 94U;

	/* dc_guard_bins excludes [0, 4), leaving the boundary bin eligible. */
	az_plus[4] = 101U;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin,
					  &peak_power) == 0);
	assert(peak_bin == 4U);
	assert(peak_power == 101U);

	az_plus[4] = 0U;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin,
					  &peak_power) == 0);
	assert(peak_bin == 100U);
	assert(peak_power == 100U);

	az_plus[98] = 1U;
	az_plus[99] = 2U;
	az_plus[102] = 4U;
	az_minus[98] = 2U;
	az_minus[99] = 3U;
	az_minus[102] = 5U;
	el_plus[98] = 3U;
	el_plus[99] = 4U;
	el_plus[102] = 6U;
	el_minus[98] = 4U;
	el_minus[99] = 5U;
	el_minus[102] = 7U;
	assert(monopulse_integrate_cw(&spectra, &cfg, 100U, &powers) == 0);
	assert_powers(&powers, 18U, 32U, 46U, 150U);
}

static void test_band_power_and_saturation(void)
{
	static uint64_t az_plus[MONOPULSE_FFT_SIZE];
	static uint64_t az_minus[MONOPULSE_FFT_SIZE];
	static uint64_t el_plus[MONOPULSE_FFT_SIZE];
	static uint64_t el_minus[MONOPULSE_FFT_SIZE];
	struct monopulse_spectrum_config cfg = valid_spectrum_config();
	struct monopulse_spectra spectra = spectra_from_arrays(az_plus, az_minus,
		el_plus, el_minus);
	struct monopulse_power_set powers;

	az_plus[63] = 100U;
	az_plus[64] = 1U;
	az_plus[65] = 2U;
	az_plus[511] = 4U;
	az_plus[512] = 100U;
	az_minus[64] = 3U;
	az_minus[511] = 5U;
	el_plus[64] = 7U;
	el_plus[511] = 11U;
	el_minus[64] = 13U;
	el_minus[511] = 17U;
	assert(monopulse_integrate_band(&spectra, &cfg, &powers) == 0);
	assert_powers(&powers, 7U, 8U, 18U, 30U);

	az_plus[64] = UINT64_MAX;
	az_plus[65] = 1U;
	az_minus[64] = UINT64_MAX;
	az_minus[65] = 1U;
	el_plus[64] = UINT64_MAX;
	el_plus[65] = 1U;
	el_minus[64] = UINT64_MAX;
	el_minus[65] = 1U;
	assert(monopulse_integrate_band(&spectra, &cfg, &powers) == 0);
	assert_powers(&powers, UINT64_MAX, UINT64_MAX, UINT64_MAX,
		      UINT64_MAX);
	az_plus[100] = UINT64_MAX;
	az_plus[101] = 1U;
	az_minus[100] = UINT64_MAX;
	az_minus[101] = 1U;
	el_plus[100] = UINT64_MAX;
	el_plus[101] = 1U;
	el_minus[100] = UINT64_MAX;
	el_minus[101] = 1U;
	assert(monopulse_integrate_cw(&spectra, &cfg, 100U, &powers) == 0);
	assert_powers(&powers, UINT64_MAX, UINT64_MAX, UINT64_MAX,
		      UINT64_MAX);

	cfg.search_bin_start = 100U;
	cfg.search_bin_stop = 101U;
	az_plus[100] = UINT64_MAX;
	az_minus[100] = UINT64_MAX;
	el_plus[100] = UINT64_MAX;
	el_minus[100] = UINT64_MAX;
	az_plus[101] = UINT64_MAX;
	az_minus[101] = UINT64_MAX;
	el_plus[101] = UINT64_MAX;
	el_minus[101] = UINT64_MAX;
	{
		uint32_t peak_bin;
		uint64_t peak_power;

		assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin,
						  &peak_power) == 0);
		assert(peak_bin == 100U);
		assert(peak_power == UINT64_MAX);
	}
}

static void test_spectrum_boundaries_and_validation(void)
{
	static uint64_t az_plus[MONOPULSE_FFT_SIZE];
	static uint64_t az_minus[MONOPULSE_FFT_SIZE];
	static uint64_t el_plus[MONOPULSE_FFT_SIZE];
	static uint64_t el_minus[MONOPULSE_FFT_SIZE];
	struct monopulse_spectrum_config cfg = valid_spectrum_config();
	struct monopulse_spectra spectra = spectra_from_arrays(az_plus, az_minus,
		el_plus, el_minus);
	struct monopulse_power_set powers;
	uint32_t peak_bin;
	uint64_t peak_power;

	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin,
					  &peak_power) == 0);
	assert(peak_bin == 8U);
	assert(peak_power == 0U);

	az_plus[0] = 1U;
	az_minus[0] = 2U;
	el_plus[0] = 3U;
	el_minus[0] = 4U;
	assert(monopulse_integrate_cw(&spectra, &cfg, 2U, &powers) == 0);
	assert_powers(&powers, 1U, 2U, 3U, 4U);
	az_plus[MONOPULSE_FFT_SIZE - 1U] = 5U;
	az_minus[MONOPULSE_FFT_SIZE - 1U] = 6U;
	el_plus[MONOPULSE_FFT_SIZE - 1U] = 7U;
	el_minus[MONOPULSE_FFT_SIZE - 1U] = 8U;
	assert(monopulse_integrate_cw(&spectra, &cfg,
					 MONOPULSE_FFT_SIZE - 3U, &powers) == 0);
	assert_powers(&powers, 5U, 6U, 7U, 8U);
	assert(monopulse_integrate_cw(&spectra, &cfg, 1U, &powers) == -EINVAL);
	assert(monopulse_integrate_cw(&spectra, &cfg,
					 MONOPULSE_FFT_SIZE - 2U, &powers) == -EINVAL);
	assert(monopulse_integrate_cw(&spectra, &cfg, 2U, NULL) == -EINVAL);
	assert(monopulse_integrate_band(&spectra, &cfg, NULL) == -EINVAL);

	assert(monopulse_find_common_peak(NULL, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	assert(monopulse_find_common_peak(&spectra, NULL, &peak_bin, &peak_power) ==
		-EINVAL);
	assert(monopulse_find_common_peak(&spectra, &cfg, NULL, &peak_power) ==
		-EINVAL);
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, NULL) ==
		-EINVAL);
	spectra.state[MONOPULSE_EL_MINUS] = NULL;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	assert(monopulse_integrate_cw(&spectra, &cfg, 2U, &powers) == -EINVAL);
	assert(monopulse_integrate_band(&spectra, &cfg, &powers) == -EINVAL);
	spectra.state[MONOPULSE_EL_MINUS] = el_minus;

	cfg.fft_size = MONOPULSE_FFT_SIZE - 1U;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	cfg = valid_spectrum_config();
	cfg.search_bin_start = 9U;
	cfg.search_bin_stop = 8U;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	cfg = valid_spectrum_config();
	cfg.search_bin_stop = MONOPULSE_FFT_SIZE;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	cfg = valid_spectrum_config();
	cfg.band_bin_start = 512U;
	cfg.band_bin_stop = 511U;
	assert(monopulse_integrate_band(&spectra, &cfg, &powers) == -EINVAL);
	cfg = valid_spectrum_config();
	cfg.band_bin_stop = MONOPULSE_FFT_SIZE;
	assert(monopulse_integrate_band(&spectra, &cfg, &powers) == -EINVAL);
	cfg = valid_spectrum_config();
	cfg.dc_guard_bins = MONOPULSE_FFT_SIZE;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
	cfg = valid_spectrum_config();
	cfg.cw_half_width = MONOPULSE_FFT_SIZE;
	assert(monopulse_find_common_peak(&spectra, &cfg, &peak_bin, &peak_power) ==
		-EINVAL);
}

static void test_axis_vectors(void)
{
	struct monopulse_axis_result r;

	assert(monopulse_compute_axis(300, 100, 1, &r) == 0);
	assert(r.numerator == 200);
	assert(r.denominator == 400);
	assert(r.error_q31 == INT32_C(1073741824));
	assert(r.valid == 1U);

	assert(monopulse_compute_axis(100, 300, 1, &r) == 0);
	assert(r.numerator == -200);
	assert(r.error_q31 == -INT32_C(1073741824));

	assert(monopulse_compute_axis(200, 200, 1, &r) == 0);
	assert(r.error_q31 == 0);

	assert(monopulse_compute_axis(1, 0, 1, &r) == 0);
	assert(r.error_q31 == INT32_MAX);
	assert(monopulse_compute_axis(0, 1, 1, &r) == 0);
	assert(r.error_q31 == INT32_MIN);

	assert(monopulse_compute_axis(2, 1, 4, &r) == 0);
	assert(r.valid == 0U);
	assert((r.flags & MONOPULSE_AXIS_DENOMINATOR_SMALL) != 0U);
}

static void test_invalid_arguments(void)
{
	struct monopulse_axis_result axis;
	struct monopulse_result result;
	struct monopulse_power_set powers = { 1, 1, 1, 1 };

	assert(monopulse_compute_axis(1, 1, 1, NULL) == -EINVAL);
	assert(monopulse_compute_axis(1, 1, 0, &axis) == -EINVAL);
	assert(monopulse_compute_result(NULL, 1, &result) == -EINVAL);
	assert(monopulse_compute_result(&powers, 1, NULL) == -EINVAL);
	assert(monopulse_compute_result(&powers, 0, &result) == -EINVAL);
}

static void test_axis_boundaries(void)
{
	struct monopulse_axis_result r;

	assert(monopulse_compute_axis(UINT64_MAX, UINT64_MAX, 1, &r) == 0);
	assert(r.denominator == UINT64_MAX);
	assert(r.numerator == 0);
	assert(r.error_q31 == 0);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);
	assert(r.valid == 1U);

	assert(monopulse_compute_axis(UINT64_MAX, 0, 1, &r) == 0);
	assert(r.numerator == INT64_MAX);
	assert(r.error_q31 == INT32_MAX);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);

	assert(monopulse_compute_axis(0, UINT64_MAX, 1, &r) == 0);
	assert(r.numerator == INT64_MIN);
	assert(r.error_q31 == INT32_MIN);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);
}

static void test_q31_rounding(void)
{
	struct monopulse_axis_result r;
	const uint64_t half_scale = UINT64_C(1) << 32;

	assert(monopulse_compute_axis(2, 1, 1, &r) == 0);
	assert(r.error_q31 == INT32_C(715827883));
	assert(monopulse_compute_axis(1, 2, 1, &r) == 0);
	assert(r.error_q31 == -INT32_C(715827883));

	/* 0.5 rounds down to the even integer zero. */
	assert(monopulse_compute_axis(half_scale + 1U, half_scale - 1U, 1,
				      &r) == 0);
	assert(r.error_q31 == 0);
	assert(monopulse_compute_axis(half_scale - 1U, half_scale + 1U, 1,
				      &r) == 0);
	assert(r.error_q31 == 0);

	/* 1.5 rounds up to the even integer two. */
	assert(monopulse_compute_axis(half_scale + 3U, half_scale - 3U, 1,
				      &r) == 0);
	assert(r.error_q31 == 2);
	assert(monopulse_compute_axis(half_scale - 3U, half_scale + 3U, 1,
				      &r) == 0);
	assert(r.error_q31 == -2);
}

static void test_independent_axes(void)
{
	struct monopulse_power_set powers = { 600, 200, 100, 300 };
	struct monopulse_result result;

	assert(monopulse_compute_result(&powers, 1, &result) == 0);
	assert(result.powers.az_plus == 600);
	assert(result.powers.el_minus == 300);
	assert(result.az.error_q31 == INT32_C(1073741824));
	assert(result.el.error_q31 == -INT32_C(1073741824));
	assert(result.az.valid == 1U);
	assert(result.el.valid == 1U);
}

static void test_state_sequence(void)
{
	static const struct monopulse_switch_outputs expected[MONOPULSE_STATE_COUNT] = {
		{0U, 0U}, {0U, 1U}, {1U, 0U}, {1U, 1U}
	};
	struct monopulse_switch_outputs actual;
	enum monopulse_state_id state = MONOPULSE_AZ_PLUS;

	for (uint32_t n = 0; n < MONOPULSE_STATE_COUNT; ++n) {
		assert(monopulse_state_outputs(state, &actual) == 0);
		assert(actual.delta_select == expected[n].delta_select);
		assert(actual.phase_180 == expected[n].phase_180);
		state = monopulse_next_state(state);
	}
	assert(state == MONOPULSE_AZ_PLUS);
}

static void test_invalid_sequence_arguments(void)
{
	struct monopulse_switch_outputs actual;
	const enum monopulse_state_id invalid_high = MONOPULSE_STATE_COUNT;
	const enum monopulse_state_id invalid_low =
		(enum monopulse_state_id)-1;

	assert(monopulse_state_outputs(invalid_high, &actual) == -EINVAL);
	assert(monopulse_state_outputs(invalid_low, &actual) == -EINVAL);
	assert(monopulse_state_outputs(MONOPULSE_AZ_PLUS, NULL) == -EINVAL);
	assert(monopulse_next_state(invalid_high) == MONOPULSE_AZ_PLUS);
	assert(monopulse_next_state(invalid_low) == MONOPULSE_AZ_PLUS);
}

int main(void)
{
	test_axis_vectors();
	test_invalid_arguments();
	test_axis_boundaries();
	test_q31_rounding();
	test_independent_axes();
	test_state_sequence();
	test_invalid_sequence_arguments();
	test_common_peak_and_cw_integration();
	test_band_power_and_saturation();
	test_spectrum_boundaries_and_validation();
	puts("CROSSCHECK powers=300,100,100,300 q31=1073741824,-1073741824");
	puts("PASS: monopulse foundation deterministic vectors passed.");
	return 0;
}
