#ifndef WIFI_RF_CAPTURE_H
#define WIFI_RF_CAPTURE_H

#include <stddef.h>
#include <stdint.h>

#include "ad9361_api.h"
#include "axi_dmac.h"
#include "wifi_rf_metrics.h"

#define WIFI_RF_FIRST_CHANNEL 1U
#define WIFI_RF_LAST_CHANNEL 13U
#define WIFI_RF_CHANNEL_COUNT 13U
#define WIFI_RF_SCAN_DWELL_MS 250U
#define WIFI_RF_MONITOR_DWELL_MS 500U
#define WIFI_RF_DMA_TIMEOUT_MS 500U
#define WIFI_RF_LO_SETTLE_MS 20U
#define WIFI_RF_MAX_BLOCKS 512U

enum wifi_rf_capture_mode {
	WIFI_RF_CAPTURE_BASELINE,
	WIFI_RF_CAPTURE_ACTIVE
};

struct wifi_rf_capture_ctx {
	struct ad9361_rf_phy *phy;
	struct axi_dmac *rx_dmac;
	int16_t *iq_buffer;
	size_t complex_samples;
	const char *last_error;
};

int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *ctx,
			     struct ad9361_rf_phy *phy,
			     struct axi_dmac *rx_dmac,
			     int16_t *iq_buffer,
			     size_t complex_samples);
int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *ctx);
uint64_t wifi_rf_channel_frequency_hz(uint8_t channel);
int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *ctx,
				uint8_t channel,
				enum wifi_rf_capture_mode mode,
				uint32_t dwell_ms,
				const struct wifi_rf_channel_metrics *baseline,
				struct wifi_rf_channel_metrics *out);

#endif
