#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "wifi_rf_metrics.h"

static void test_zero_and_constant(void)
{
	int16_t zero[8] = {0};
	int16_t quarter_scale[8] = {
		16384, 16384, 16384, 16384,
		16384, 16384, 16384, 16384
	};
	struct wifi_rf_block_metrics m;

	assert(wifi_rf_analyze_block(zero, 4, &m) == 0);
	assert(m.mean_power == 0);
	assert(m.peak_abs == 0);
	assert(m.clip_count == 0);
	assert(wifi_rf_power_cdbfs16(m.mean_power) == WIFI_RF_ZERO_CDBFS);

	assert(wifi_rf_analyze_block(quarter_scale, 4, &m) == 0);
	assert(m.mean_power == 536870912ULL);
	assert(m.peak_abs == 16384);
	assert(m.clip_count == 0);
	assert(wifi_rf_power_cdbfs16(m.mean_power) >= -603);
	assert(wifi_rf_power_cdbfs16(m.mean_power) <= -601);
	assert(wifi_rf_peak_cdbfs16(m.peak_abs) >= -603);
	assert(wifi_rf_peak_cdbfs16(m.peak_abs) <= -601);
}

static void test_clipping_median_and_verdict(void)
{
	int16_t clipped[4] = {32767, -32768, 100, -100};
	uint64_t values[5] = {40, 10, 30, 50, 20};
	struct wifi_rf_block_metrics m;
	struct wifi_rf_channel_metrics baseline = {
		.rssi_cdb = -6000, .power_cdbfs16 = -4800,
		.burst_percent = 3
	};
	struct wifi_rf_channel_metrics active = {
		.rssi_cdb = -5600, .power_cdbfs16 = -4400,
		.burst_percent = 24
	};
	struct wifi_rf_metric_delta delta;

	assert(wifi_rf_analyze_block(clipped, 2, &m) == 0);
	assert(m.peak_abs == 32768U);
	assert(m.clip_count == 1U);
	assert(wifi_rf_median_u64(values, 5) == 30U);

	delta = wifi_rf_delta(&baseline, &active);
	assert(delta.rssi_cdb == 400);
	assert(delta.power_cdb == 400);
	assert(delta.burst_pp == 21);
	assert(wifi_rf_classify(&delta, 3, 0, 10000) == WIFI_RF_ACTIVITY_PASS);
	assert(wifi_rf_classify(&delta, 2, 0, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	assert(wifi_rf_classify(&delta, 3, 11, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	baseline.rssi_cdb = WIFI_RF_RSSI_INVALID_CDB;
	delta = wifi_rf_delta(&baseline, &active);
	assert(delta.rssi_cdb == WIFI_RF_RSSI_INVALID_CDB);
	assert(wifi_rf_classify(&delta, 3, 0, 10000) == WIFI_RF_ACTIVITY_PASS);
}

int main(void)
{
	test_zero_and_constant();
	test_clipping_median_and_verdict();
	puts("PASS: Wi-Fi RF metrics deterministic vectors passed.");
	return 0;
}
