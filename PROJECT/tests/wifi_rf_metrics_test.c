#include <assert.h>
#include <errno.h>
#include <limits.h>
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
	assert(m.complex_samples == 4);
	assert(m.peak_abs == 0);
	assert(m.clip_count == 0);
	assert(wifi_rf_power_cdbfs16(m.mean_power) == WIFI_RF_ZERO_CDBFS);
	assert(wifi_rf_peak_cdbfs16(m.peak_abs) == WIFI_RF_ZERO_CDBFS);

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

static void test_input_and_threshold_boundaries(void)
{
	int16_t clip_boundary[4] = {32111, 0, 32112, 0};
	uint64_t even_values[4] = {4, 1, 3, 2};
	struct wifi_rf_block_metrics m;
	struct wifi_rf_metric_delta delta = {
		.rssi_cdb = WIFI_RF_RSSI_DELTA_PASS_CDB,
		.power_cdb = WIFI_RF_POWER_DELTA_PASS_CDB,
		.burst_pp = WIFI_RF_BURST_DELTA_PASS_PP - 1
	};

	assert(wifi_rf_analyze_block(NULL, 1, &m) == -EINVAL);
	assert(wifi_rf_analyze_block(clip_boundary, 0, &m) == -EINVAL);
	assert(wifi_rf_analyze_block(clip_boundary, 1, NULL) == -EINVAL);
#if SIZE_MAX == UINT32_MAX
	assert(wifi_rf_analyze_block(clip_boundary,
		(SIZE_MAX / 2U) + 2U, &m) == -EINVAL);
#else
	assert(wifi_rf_analyze_block(clip_boundary,
		(size_t)UINT32_MAX + 1U, &m) == -EINVAL);
#endif
	assert(wifi_rf_analyze_block(clip_boundary, 2, &m) == 0);
	assert(m.complex_samples == 2);
	assert(m.peak_abs == WIFI_RF_CLIP_ABS);
	assert(m.clip_count == 1);

	assert(wifi_rf_median_u64(even_values, 4) == 3);
	assert(wifi_rf_median_u64(NULL, 4) == 0);
	assert(wifi_rf_median_u64(even_values, 0) == 0);

	assert(wifi_rf_classify(&delta, WIFI_RF_REQUIRED_MONITOR_HITS,
		10, 10000) == WIFI_RF_ACTIVITY_PASS);
	assert(wifi_rf_classify(&delta, WIFI_RF_REQUIRED_MONITOR_HITS,
		11, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	delta.power_cdb = WIFI_RF_POWER_DELTA_PASS_CDB - 1;
	delta.burst_pp = WIFI_RF_BURST_DELTA_PASS_PP;
	assert(wifi_rf_classify(&delta, WIFI_RF_REQUIRED_MONITOR_HITS,
		0, 10000) == WIFI_RF_ACTIVITY_PASS);
	assert(wifi_rf_classify(NULL, WIFI_RF_REQUIRED_MONITOR_HITS,
		0, 10000) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
	assert(wifi_rf_classify(&delta, WIFI_RF_REQUIRED_MONITOR_HITS,
		0, 0) == WIFI_RF_ACTIVITY_INCONCLUSIVE);
}

static int check_i32(int32_t actual, int32_t expected, const char *label)
{
	if (actual == expected)
		return 0;
	fprintf(stderr, "FAIL: %s: expected %ld, got %ld\n", label,
		(long)expected, (long)actual);
	return 1;
}

static int test_delta_saturates_without_losing_rssi_sentinel(void)
{
	struct wifi_rf_channel_metrics baseline = {
		.rssi_cdb = INT32_MIN + 1,
		.power_cdbfs16 = WIFI_RF_ZERO_CDBFS
	};
	struct wifi_rf_channel_metrics active = {
		.rssi_cdb = INT32_MAX,
		.power_cdbfs16 = 0
	};
	struct wifi_rf_metric_delta delta = wifi_rf_delta(&baseline, &active);

	if (check_i32(delta.rssi_cdb, INT32_MAX, "positive RSSI delta"))
		return 1;
	if (check_i32(delta.power_cdb, INT32_MAX, "positive power delta"))
		return 1;

	baseline.rssi_cdb = INT32_MAX;
	baseline.power_cdbfs16 = 0;
	active.rssi_cdb = INT32_MIN + 1;
	active.power_cdbfs16 = WIFI_RF_ZERO_CDBFS;
	delta = wifi_rf_delta(&baseline, &active);
	if (check_i32(delta.rssi_cdb, INT32_MIN, "negative RSSI delta"))
		return 1;
	if (check_i32(delta.power_cdb, INT32_MIN, "negative power delta"))
		return 1;

	baseline.rssi_cdb = WIFI_RF_RSSI_INVALID_CDB;
	active.rssi_cdb = INT32_MAX;
	delta = wifi_rf_delta(&baseline, &active);
	if (check_i32(delta.rssi_cdb, WIFI_RF_RSSI_INVALID_CDB,
		      "invalid RSSI sentinel"))
		return 1;
	return 0;
}

int main(void)
{
	test_zero_and_constant();
	test_clipping_median_and_verdict();
	test_input_and_threshold_boundaries();
	if (test_delta_saturates_without_losing_rssi_sentinel())
		return 1;
	puts("PASS: Wi-Fi RF metrics deterministic vectors passed.");
	return 0;
}
