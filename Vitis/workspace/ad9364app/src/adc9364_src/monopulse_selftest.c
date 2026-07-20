#include "monopulse_selftest.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "ad9361_api.h"
#include "monopulse_math.h"
#include "monopulse_sequence.h"
#include "monopulse_spectrum.h"

#define MONOPULSE_SELFTEST_SAMPLE_RATE_HZ UINT32_C(30720000)
#define MONOPULSE_SELFTEST_RX_BANDWIDTH_HZ UINT32_C(10000000)
#define MONOPULSE_SELFTEST_TX_ATTENUATION_MDB UINT32_C(89750)
#define MONOPULSE_SELFTEST_HALF_Q31 INT32_C(1073741824)

static int32_t monopulse_selftest_fail(const char *stage)
{
	printf("MONOPULSE_FOUNDATION: FAIL stage=%s\n", stage);
	return -EIO;
}

static int32_t monopulse_selftest_verify_sequence(void)
{
	static const enum monopulse_state_id states[MONOPULSE_STATE_COUNT] = {
		MONOPULSE_AZ_PLUS,
		MONOPULSE_AZ_MINUS,
		MONOPULSE_EL_PLUS,
		MONOPULSE_EL_MINUS
	};
	uint32_t index;

	for (index = 0U; index < MONOPULSE_STATE_COUNT; index++) {
		enum monopulse_state_id expected =
			states[(index + 1U) % MONOPULSE_STATE_COUNT];

		if (monopulse_next_state(states[index]) != expected) {
			return -EIO;
		}
	}

	return 0;
}

static int32_t monopulse_selftest_verify_spectrum(const char **failure_stage)
{
	static uint64_t storage[MONOPULSE_STATE_COUNT][MONOPULSE_FFT_SIZE];
	struct monopulse_spectrum_config cfg = {
		.fft_size = MONOPULSE_FFT_SIZE,
		.search_bin_start = 0U,
		.search_bin_stop = 101U,
		.dc_guard_bins = 4U,
		.cw_half_width = 2U,
		.band_bin_start = 64U,
		.band_bin_stop = 65U
	};
	struct monopulse_spectra spectra = {
		.state = { storage[MONOPULSE_AZ_PLUS],
			   storage[MONOPULSE_AZ_MINUS],
			   storage[MONOPULSE_EL_PLUS],
			   storage[MONOPULSE_EL_MINUS] }
	};
	struct monopulse_power_set powers;
	uint32_t peak_bin;
	uint64_t peak_power;

	memset(storage, 0, sizeof(storage));
	storage[MONOPULSE_AZ_PLUS][3] = 1000U;
	storage[MONOPULSE_AZ_PLUS][100] = 10U;
	storage[MONOPULSE_AZ_MINUS][100] = 20U;
	storage[MONOPULSE_EL_PLUS][100] = 30U;
	storage[MONOPULSE_EL_MINUS][100] = 40U;
	storage[MONOPULSE_AZ_PLUS][101] = 1U;
	storage[MONOPULSE_AZ_MINUS][101] = 2U;
	storage[MONOPULSE_EL_PLUS][101] = 3U;
	storage[MONOPULSE_EL_MINUS][101] = 94U;
	if (monopulse_find_common_peak(&spectra, &cfg, &peak_bin,
					&peak_power) != 0 ||
	    peak_bin != 100U || peak_power != 100U) {
		*failure_stage = "SPECTRUM_PEAK";
		return -EIO;
	}

	storage[MONOPULSE_AZ_PLUS][98] = 1U;
	storage[MONOPULSE_AZ_PLUS][99] = 2U;
	storage[MONOPULSE_AZ_PLUS][102] = 4U;
	storage[MONOPULSE_AZ_MINUS][98] = 2U;
	storage[MONOPULSE_AZ_MINUS][99] = 3U;
	storage[MONOPULSE_AZ_MINUS][102] = 5U;
	storage[MONOPULSE_EL_PLUS][98] = 3U;
	storage[MONOPULSE_EL_PLUS][99] = 4U;
	storage[MONOPULSE_EL_PLUS][102] = 6U;
	storage[MONOPULSE_EL_MINUS][98] = 4U;
	storage[MONOPULSE_EL_MINUS][99] = 5U;
	storage[MONOPULSE_EL_MINUS][102] = 7U;
	if (monopulse_integrate_cw(&spectra, &cfg, peak_bin, &powers) != 0 ||
	    powers.az_plus != 18U || powers.az_minus != 32U ||
	    powers.el_plus != 46U || powers.el_minus != 150U) {
		*failure_stage = "SPECTRUM_CW";
		return -EIO;
	}

	storage[MONOPULSE_AZ_PLUS][64] = 1U;
	storage[MONOPULSE_AZ_PLUS][65] = 2U;
	storage[MONOPULSE_AZ_MINUS][64] = 3U;
	storage[MONOPULSE_AZ_MINUS][65] = 5U;
	storage[MONOPULSE_EL_PLUS][64] = 7U;
	storage[MONOPULSE_EL_PLUS][65] = 11U;
	storage[MONOPULSE_EL_MINUS][64] = 13U;
	storage[MONOPULSE_EL_MINUS][65] = 17U;
	if (monopulse_integrate_band(&spectra, &cfg, &powers) != 0 ||
	    powers.az_plus != 3U || powers.az_minus != 8U ||
	    powers.el_plus != 18U || powers.el_minus != 30U) {
		*failure_stage = "SPECTRUM_BAND";
		return -EIO;
	}

	for (uint32_t state = 0U; state < MONOPULSE_STATE_COUNT; state++) {
		storage[state][64] = UINT64_MAX;
		storage[state][65] = 1U;
	}
	if (monopulse_integrate_band(&spectra, &cfg, &powers) != 0 ||
	    powers.az_plus != UINT64_MAX || powers.az_minus != UINT64_MAX ||
	    powers.el_plus != UINT64_MAX || powers.el_minus != UINT64_MAX) {
		*failure_stage = "SPECTRUM_SATURATION";
		return -EIO;
	}

	return 0;
}

int32_t monopulse_selftest_run(struct ad9361_rf_phy *phy)
{
	struct monopulse_power_set powers = {
		.az_plus = 300U,
		.az_minus = 100U,
		.el_plus = 100U,
		.el_minus = 300U
	};
	struct monopulse_result result;
	uint32_t sample_rate_hz;
	uint32_t rx_bandwidth_hz;
	uint32_t tx_attenuation_mdb;
	uint64_t rx_lo_hz;
	int32_t rx_gain_db;
	int32_t status;
	const char *spectrum_failure_stage = "SPECTRUM";

	if (phy == NULL) {
		return monopulse_selftest_fail("ARG");
	}

	status = ad9361_get_rx_sampling_freq(phy, &sample_rate_hz);
	if (status < 0) {
		return monopulse_selftest_fail("RX_SAMPLE_RATE_READ");
	}
	if (sample_rate_hz != MONOPULSE_SELFTEST_SAMPLE_RATE_HZ) {
		return monopulse_selftest_fail("RX_SAMPLE_RATE_VALUE");
	}

	status = ad9361_get_rx_rf_bandwidth(phy, &rx_bandwidth_hz);
	if (status < 0) {
		return monopulse_selftest_fail("RX_BANDWIDTH_READ");
	}
	if (rx_bandwidth_hz != MONOPULSE_SELFTEST_RX_BANDWIDTH_HZ) {
		return monopulse_selftest_fail("RX_BANDWIDTH_VALUE");
	}

	status = ad9361_get_rx_lo_freq(phy, &rx_lo_hz);
	if (status < 0) {
		return monopulse_selftest_fail("RX_LO_READ");
	}

	status = ad9361_get_rx_rf_gain(phy, 0U, &rx_gain_db);
	if (status < 0) {
		return monopulse_selftest_fail("RX_GAIN_READ");
	}

	status = ad9361_get_tx_attenuation(phy, 0U, &tx_attenuation_mdb);
	if (status < 0) {
		return monopulse_selftest_fail("TX_ATTENUATION_READ");
	}
	if (tx_attenuation_mdb != MONOPULSE_SELFTEST_TX_ATTENUATION_MDB) {
		return monopulse_selftest_fail("TX_ATTENUATION_VALUE");
	}

	status = monopulse_compute_result(&powers, 1U, &result);
	if ((status != 0) || (result.az.valid == 0U) || (result.el.valid == 0U) ||
	    (result.az.flags != 0U) || (result.el.flags != 0U) ||
	    (result.az.error_q31 != MONOPULSE_SELFTEST_HALF_Q31) ||
	    (result.el.error_q31 != -MONOPULSE_SELFTEST_HALF_Q31)) {
		return monopulse_selftest_fail("MATH");
	}

	if (monopulse_selftest_verify_sequence() != 0) {
		return monopulse_selftest_fail("SEQUENCE");
	}
	if (monopulse_selftest_verify_spectrum(&spectrum_failure_stage) != 0) {
		return monopulse_selftest_fail(spectrum_failure_stage);
	}

	printf("MONOPULSE_RF: PASS fs=%" PRIu32 " bw=%" PRIu32
	       " lo=%" PRIu64 " gain=%" PRId32 " tx_att=%" PRIu32 "\n",
	       sample_rate_hz, rx_bandwidth_hz, rx_lo_hz, rx_gain_db,
	       tx_attenuation_mdb);
	printf("MONOPULSE_FOUNDATION: PASS\n");
	return 0;
}
