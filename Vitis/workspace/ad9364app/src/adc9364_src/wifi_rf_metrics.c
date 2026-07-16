#include "wifi_rf_metrics.h"

#include <errno.h>
#include <limits.h>
#include <math.h>

#define WIFI_RF_COMPLEX_FULL_SCALE_POWER 2147483648.0

static uint16_t abs_i16(int16_t value)
{
	int32_t widened = value;
	return (uint16_t)(widened < 0 ? -widened : widened);
}

int32_t wifi_rf_analyze_block(const int16_t *iq, size_t complex_samples,
			      struct wifi_rf_block_metrics *out)
{
	uint64_t sum = 0;
	uint32_t clips = 0;
	uint16_t peak = 0;
	size_t n;

	if (!iq || !out || complex_samples == 0 || complex_samples > UINT32_MAX)
		return -EINVAL;

	for (n = 0; n < complex_samples; n++) {
		int32_t i = iq[2 * n];
		int32_t q = iq[2 * n + 1];
		uint16_t ai = abs_i16((int16_t)i);
		uint16_t aq = abs_i16((int16_t)q);

		sum += (uint64_t)(i * i) + (uint64_t)(q * q);
		if (ai > peak) peak = ai;
		if (aq > peak) peak = aq;
		if (ai >= WIFI_RF_CLIP_ABS || aq >= WIFI_RF_CLIP_ABS)
			clips++;
	}

	out->mean_power = sum / complex_samples;
	out->complex_samples = (uint32_t)complex_samples;
	out->clip_count = clips;
	out->peak_abs = peak;
	return 0;
}

uint64_t wifi_rf_median_u64(uint64_t *values, size_t count)
{
	size_t i, j;
	if (!values || count == 0) return 0;
	for (i = 1; i < count; i++) {
		uint64_t key = values[i];
		j = i;
		while (j > 0 && values[j - 1] > key) {
			values[j] = values[j - 1];
			j--;
		}
		values[j] = key;
	}
	return values[count / 2];
}

int32_t wifi_rf_power_cdbfs16(uint64_t mean_power)
{
	double cdb;
	if (mean_power == 0) return WIFI_RF_ZERO_CDBFS;
	cdb = 1000.0 * log10((double)mean_power /
				     WIFI_RF_COMPLEX_FULL_SCALE_POWER);
	return (int32_t)lround(cdb);
}

int32_t wifi_rf_peak_cdbfs16(uint16_t peak_abs)
{
	double cdb;
	if (peak_abs == 0) return WIFI_RF_ZERO_CDBFS;
	cdb = 2000.0 * log10((double)peak_abs / 32768.0);
	return (int32_t)lround(cdb);
}

struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *baseline,
	const struct wifi_rf_channel_metrics *active)
{
	struct wifi_rf_metric_delta delta = {0};
	if (!baseline || !active) return delta;
	delta.rssi_cdb = baseline->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB ||
		active->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB ?
		WIFI_RF_RSSI_INVALID_CDB : active->rssi_cdb - baseline->rssi_cdb;
	delta.power_cdb = active->power_cdbfs16 - baseline->power_cdbfs16;
	delta.burst_pp = (int32_t)active->burst_percent -
			 (int32_t)baseline->burst_percent;
	return delta;
}

enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *delta,
	uint32_t monitor_hits,
	uint32_t clip_count,
	uint32_t complex_samples)
{
	uint32_t indicators = 0;
	if (!delta || complex_samples == 0) return WIFI_RF_ACTIVITY_INCONCLUSIVE;
	if ((uint64_t)clip_count * 1000U > complex_samples)
		return WIFI_RF_ACTIVITY_INCONCLUSIVE;
	if (delta->rssi_cdb != WIFI_RF_RSSI_INVALID_CDB &&
	    delta->rssi_cdb >= WIFI_RF_RSSI_DELTA_PASS_CDB) indicators++;
	if (delta->power_cdb >= WIFI_RF_POWER_DELTA_PASS_CDB) indicators++;
	if (delta->burst_pp >= WIFI_RF_BURST_DELTA_PASS_PP) indicators++;
	return indicators >= 2 && monitor_hits >= WIFI_RF_REQUIRED_MONITOR_HITS ?
		WIFI_RF_ACTIVITY_PASS : WIFI_RF_ACTIVITY_INCONCLUSIVE;
}
