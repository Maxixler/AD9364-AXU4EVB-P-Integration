#ifndef WIFI_RF_METRICS_H
#define WIFI_RF_METRICS_H

#include <stddef.h>
#include <stdint.h>

#define WIFI_RF_CLIP_ABS 32112U
#define WIFI_RF_RSSI_DELTA_PASS_CDB 300
#define WIFI_RF_POWER_DELTA_PASS_CDB 300
#define WIFI_RF_BURST_DELTA_PASS_PP 20
#define WIFI_RF_REQUIRED_MONITOR_HITS 3U
#define WIFI_RF_ZERO_CDBFS INT32_MIN
#define WIFI_RF_RSSI_INVALID_CDB INT32_MIN

struct wifi_rf_block_metrics {
	uint64_t mean_power;
	uint32_t complex_samples;
	uint32_t clip_count;
	uint16_t peak_abs;
};

struct wifi_rf_channel_metrics {
	int32_t rssi_cdb;
	int32_t power_cdbfs16;
	int32_t peak_cdbfs16;
	int32_t gain_db;
	uint64_t baseline_median_power;
	uint32_t clip_count;
	uint32_t complex_samples;
	uint32_t dma_blocks;
	uint8_t burst_percent;
};

struct wifi_rf_metric_delta {
	int32_t rssi_cdb;
	int32_t power_cdb;
	int32_t burst_pp;
};

enum wifi_rf_activity_verdict {
	WIFI_RF_ACTIVITY_INCONCLUSIVE = 0,
	WIFI_RF_ACTIVITY_PASS = 1
};

int32_t wifi_rf_analyze_block(const int16_t *iq, size_t complex_samples,
			      struct wifi_rf_block_metrics *out);
uint64_t wifi_rf_median_u64(uint64_t *values, size_t count);
int32_t wifi_rf_power_cdbfs16(uint64_t mean_power);
int32_t wifi_rf_peak_cdbfs16(uint16_t peak_abs);
struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *baseline,
	const struct wifi_rf_channel_metrics *active);
enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *delta,
	uint32_t monitor_hits,
	uint32_t clip_count,
	uint32_t complex_samples);

#endif
