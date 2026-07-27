#include "wifi_rf_capture.h"

#include <errno.h>
#include <limits.h>
#include <string.h>

#include "no_os_delay.h"
#include "xil_cache.h"

static uint64_t now_us(void)
{
	struct no_os_time now = no_os_get_time();
	return (uint64_t)now.s * 1000000ULL + now.us;
}

int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *ctx,
			     struct ad9361_rf_phy *phy,
			     struct axi_dmac *rx_dmac,
			     int16_t *iq_buffer,
			     size_t complex_samples)
{
	size_t bytes;
	uintptr_t addr;

	if (!ctx) return -EINVAL;
	ctx->last_error = "ARG_ERROR";
	if (!phy || !rx_dmac || !iq_buffer || complex_samples == 0 ||
	    complex_samples > SIZE_MAX / (2U * sizeof(int16_t)) ||
	    complex_samples > UINT32_MAX / WIFI_RF_MAX_BLOCKS ||
	    complex_samples > UINT32_MAX / (2U * sizeof(int16_t)))
		return -EINVAL;
	bytes = complex_samples * 2U * sizeof(int16_t);
	addr = (uintptr_t)iq_buffer;
	if ((addr & (WIFI_RF_CACHE_LINE_BYTES - 1U)) != 0U ||
	    (bytes & (WIFI_RF_CACHE_LINE_BYTES - 1U)) != 0U)
		return -EINVAL;
#if UINTPTR_MAX > UINT32_MAX
	if (addr > UINT32_MAX)
		return -EINVAL;
#endif
	if (bytes - 1U > (size_t)(UINT32_MAX - (uint32_t)addr))
		return -EINVAL;
	ctx->phy = phy;
	ctx->rx_dmac = rx_dmac;
	ctx->iq_buffer = iq_buffer;
	ctx->complex_samples = complex_samples;
	ctx->last_error = "NONE";
	return 0;
}

int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *ctx)
{
	uint32_t port = UINT32_MAX;
	uint32_t ensm = UINT32_MAX;
	int32_t ret;
	if (!ctx) return -EINVAL;
	ctx->last_error = "ARG_ERROR";
	if (!ctx->phy) return -EINVAL;
	ctx->last_error = "RX_ONLY_ERROR";
	ret = ad9361_set_rx_rf_port_input(ctx->phy, B_BALANCED);
	if (ret < 0) return ret;
	ret = ad9361_get_rx_rf_port_input(ctx->phy, &port);
	if (ret < 0 || port != B_BALANCED) return ret < 0 ? ret : -EIO;
	ret = ad9361_set_tx_attenuation(ctx->phy, 0, 89750);
	if (ret < 0) return ret;
	ret = ad9361_get_en_state_machine_mode(ctx->phy, &ensm);
	if (ret < 0) return ret;
	if (ensm == ENSM_MODE_FDD || ensm == ENSM_MODE_PINCTRL_FDD_INDEP) {
		ctx->last_error = "NONE";
		return 0;
	}
	ret = ad9361_set_en_state_machine_mode(ctx->phy, ENSM_MODE_RX);
	if (ret < 0) return ret;
	ret = ad9361_get_en_state_machine_mode(ctx->phy, &ensm);
	if (ret < 0 || ensm != ENSM_MODE_RX) return ret < 0 ? ret : -EIO;
	ctx->last_error = "NONE";
	return 0;
}

uint64_t wifi_rf_channel_frequency_hz(uint8_t channel)
{
	if (channel < WIFI_RF_FIRST_CHANNEL || channel > WIFI_RF_LAST_CHANNEL)
		return 0;
	return 2412000000ULL + (uint64_t)(channel - 1U) * 5000000ULL;
}

static int32_t capture_one_block(struct wifi_rf_capture_ctx *ctx,
				 struct wifi_rf_block_metrics *metrics)
{
	struct axi_dma_transfer transfer = {
		.size = (uint32_t)(ctx->complex_samples * 2U * sizeof(int16_t)),
		.transfer_done = 0,
		.cyclic = NO,
		.src_addr = 0,
		.dest_addr = (uint32_t)(uintptr_t)ctx->iq_buffer
	};
	int32_t ret;
	ctx->last_error = "DMA_ERROR";
	Xil_DCacheInvalidateRange((uintptr_t)ctx->iq_buffer, transfer.size);
	ctx->rx_dmac->transfer.transfer_done = false;
	ret = axi_dmac_transfer_start(ctx->rx_dmac, &transfer);
	if (ret < 0) return ret;
	ret = axi_dmac_transfer_wait_completion(ctx->rx_dmac, WIFI_RF_DMA_TIMEOUT_MS);
	if (ret < 0) return ret;
	Xil_DCacheInvalidateRange((uintptr_t)ctx->iq_buffer, transfer.size);
	ctx->last_error = "ANALYZE_ERROR";
	return wifi_rf_analyze_block(ctx->iq_buffer, ctx->complex_samples, metrics);
}

int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *ctx,
				uint8_t channel,
				enum wifi_rf_capture_mode mode,
				uint32_t dwell_ms,
				const struct wifi_rf_channel_metrics *baseline,
				struct wifi_rf_channel_metrics *out)
{
	uint64_t block_power[WIFI_RF_MAX_BLOCKS];
	uint64_t sum_power = 0, start, threshold;
	uint32_t blocks = 0, clips = 0, samples = 0, bursts = 0;
	uint16_t peak = 0;
	struct wifi_rf_block_metrics block;
	struct rf_rssi rssi = {0};
	uint64_t frequency = wifi_rf_channel_frequency_hz(channel);
	int32_t gain_db, ret;

	if (!ctx) return -EINVAL;
	ctx->last_error = "ARG_ERROR";
	if (!out || !ctx->phy || !ctx->rx_dmac || !ctx->iq_buffer ||
	    !ctx->complex_samples || !frequency || !dwell_ms)
		return -EINVAL;
	if (mode != WIFI_RF_CAPTURE_BASELINE &&
	    mode != WIFI_RF_CAPTURE_ACTIVE) return -EINVAL;
	if (mode == WIFI_RF_CAPTURE_ACTIVE && !baseline) return -EINVAL;
	memset(out, 0, sizeof(*out));

	ctx->last_error = "LO_ERROR";
	ret = ad9361_set_rx_lo_freq(ctx->phy, frequency);
	if (ret < 0) return ret;
	ctx->last_error = "GAIN_ERROR";
	if (mode == WIFI_RF_CAPTURE_BASELINE) {
		ret = ad9361_set_rx_gain_control_mode(ctx->phy, 0,
						      RF_GAIN_SLOWATTACK_AGC);
		if (ret < 0) return ret;
		no_os_mdelay(WIFI_RF_LO_SETTLE_MS);
		ret = ad9361_get_rx_rf_gain(ctx->phy, 0, &gain_db);
		if (ret < 0) return ret;
	} else {
		gain_db = baseline->gain_db;
		no_os_mdelay(WIFI_RF_LO_SETTLE_MS);
	}
	ret = ad9361_set_rx_gain_control_mode(ctx->phy, 0, RF_GAIN_MGC);
	if (ret < 0) return ret;
	ret = ad9361_set_rx_rf_gain(ctx->phy, 0, gain_db);
	if (ret < 0) return ret;

	start = now_us();
	do {
		ret = capture_one_block(ctx, &block);
		if (ret < 0) return ret;
		block_power[blocks] = block.mean_power;
		sum_power += block.mean_power;
		clips += block.clip_count;
		samples += block.complex_samples;
		if (block.peak_abs > peak) peak = block.peak_abs;
		blocks++;
	} while (blocks < WIFI_RF_MAX_BLOCKS &&
		 now_us() - start < (uint64_t)dwell_ms * 1000ULL);

	ret = ad9361_get_rx_rssi(ctx->phy, 0, &rssi);
	if (ret < 0 || rssi.multiplier <= 0) {
		out->rssi_cdb = WIFI_RF_RSSI_INVALID_CDB;
	} else {
		out->rssi_cdb = -(int32_t)(((uint64_t)rssi.symbol * 100U +
					      (uint32_t)rssi.multiplier / 2U) /
					     (uint32_t)rssi.multiplier);
	}
	out->gain_db = gain_db;
	out->dma_blocks = blocks;
	out->complex_samples = samples;
	out->clip_count = clips;
	out->power_cdbfs16 = wifi_rf_power_cdbfs16(sum_power / blocks);
	out->peak_cdbfs16 = wifi_rf_peak_cdbfs16(peak);
	out->baseline_median_power = mode == WIFI_RF_CAPTURE_BASELINE ?
		wifi_rf_median_u64(block_power, blocks) : baseline->baseline_median_power;
	threshold = out->baseline_median_power > UINT64_MAX / 4U ?
		UINT64_MAX : out->baseline_median_power * 4U;
	for (uint32_t n = 0; n < blocks; n++)
		if (block_power[n] > threshold) bursts++;
	out->burst_percent = (uint8_t)((bursts * 100U + blocks / 2U) / blocks);
	ctx->last_error = "NONE";
	return 0;
}
