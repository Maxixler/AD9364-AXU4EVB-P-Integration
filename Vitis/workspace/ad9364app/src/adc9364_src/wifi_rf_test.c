#include "wifi_rf_test.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>

#include "wifi_rf_capture.h"
#include "wifi_rf_metrics.h"
#include "no_os_delay.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"

#define WIFI_RF_MONITOR_WINDOWS 20U

static void wait_for_enter(void)
{
	char c;

	do {
		c = (char)inbyte();
	} while (c != '\r' && c != '\n');
	no_os_mdelay(20U);
	while (XUartPs_IsReceiveData(STDIN_BASEADDRESS))
		(void)inbyte();
}

static void print_centi_db(int32_t value)
{
	uint32_t magnitude;

	if (value == WIFI_RF_ZERO_CDBFS) {
		printf("-INF");
		return;
	}
	if (value < 0) {
		printf("-");
		magnitude = (uint32_t)(-(int64_t)value);
	} else {
		printf("+");
		magnitude = (uint32_t)value;
	}
	printf("%"PRIu32".%02"PRIu32, magnitude / 100U, magnitude % 100U);
}

static void print_channel(uint8_t channel,
			  const struct wifi_rf_channel_metrics *metrics)
{
	uint64_t frequency_mhz = wifi_rf_channel_frequency_hz(channel) /
		UINT64_C(1000000);

	printf("CH=%02u FREQ=%"PRIu64"MHz GAIN=%"PRIi32"dB RSSI=",
	       (unsigned int)channel, frequency_mhz, metrics->gain_db);
	if (metrics->rssi_cdb == WIFI_RF_RSSI_INVALID_CDB)
		printf("ERROR");
	else
		print_centi_db(metrics->rssi_cdb);
	printf("dB PWR=");
	print_centi_db(metrics->power_cdbfs16);
	printf("dBFS16 PEAK=");
	print_centi_db(metrics->peak_cdbfs16);
	printf("dBFS16 CLIP=%"PRIu32" BURST=%u%% BLOCKS=%"PRIu32" DMA=OK\n",
	       metrics->clip_count, (unsigned int)metrics->burst_percent,
	       metrics->dma_blocks);
}

static int64_t activity_score(const struct wifi_rf_metric_delta *delta)
{
	int64_t rssi = delta->rssi_cdb != WIFI_RF_RSSI_INVALID_CDB &&
			delta->rssi_cdb > 0 ? delta->rssi_cdb : 0;
	int64_t power = delta->power_cdb > 0 ? delta->power_cdb : 0;
	int64_t burst = delta->burst_pp > 0 ?
		(int64_t)delta->burst_pp * INT64_C(100) : 0;

	return rssi + power + burst;
}

static int clipping_above_limit(uint64_t clip_count,
				uint64_t complex_samples)
{
	return clip_count > complex_samples / UINT64_C(1000);
}

static enum wifi_rf_activity_verdict classify_activity(
	const struct wifi_rf_metric_delta *delta,
	uint32_t monitor_hits,
	uint64_t clip_count,
	uint64_t complex_samples)
{
	if (clipping_above_limit(clip_count, complex_samples))
		return WIFI_RF_ACTIVITY_INCONCLUSIVE;
	if (clip_count <= UINT32_MAX && complex_samples <= UINT32_MAX)
		return wifi_rf_classify(delta, monitor_hits, (uint32_t)clip_count,
					(uint32_t)complex_samples);

	/* Clipping was checked above using the full-width totals. */
	return wifi_rf_classify(delta, monitor_hits, 0U, 1U);
}

int32_t wifi_rf_test_run(struct ad9361_rf_phy *phy,
			 struct axi_dmac *rx_dmac,
			 int16_t *iq_buffer,
			 size_t complex_samples)
{
	struct wifi_rf_capture_ctx ctx;
	struct wifi_rf_channel_metrics baseline[WIFI_RF_CHANNEL_COUNT];
	struct wifi_rf_channel_metrics active[WIFI_RF_CHANNEL_COUNT];
	struct wifi_rf_channel_metrics monitor;
	struct wifi_rf_metric_delta selected_delta = {0};
	enum wifi_rf_activity_verdict verdict;
	int64_t best_score = INT64_MIN;
	uint64_t total_clip = 0, total_samples = 0;
	uint32_t monitor_hits = 0, selected = 0;
	uint8_t current_channel = 0;
	int32_t ret;

	ret = wifi_rf_capture_init(&ctx, phy, rx_dmac, iq_buffer, complex_samples);
	if (ret < 0)
		goto sample_format_fail;
	ret = wifi_rf_prepare_rx_only(&ctx);
	if (ret < 0)
		goto rx_only_fail;
	printf("RX_ONLY: PASS port=RXB fs=30.72MSPS bw=18MHz\n");

	printf("Hotspot kapali olmali. Hazir oldugunuzda Enter'a basin.\n");
	wait_for_enter();
	printf("BASELINE_SCAN: START channels=1-13 dwell=250ms\n");
	for (uint32_t n = 0; n < WIFI_RF_CHANNEL_COUNT; n++) {
		uint8_t channel = (uint8_t)(n + WIFI_RF_FIRST_CHANNEL);

		current_channel = channel;
		ret = wifi_rf_capture_channel(&ctx, channel,
			WIFI_RF_CAPTURE_BASELINE, WIFI_RF_SCAN_DWELL_MS,
			NULL, &baseline[n]);
		if (ret < 0)
			goto channel_fail;
		print_channel(channel, &baseline[n]);
	}

	printf("Hotspot 2.4 GHz modunda acik ve trafik aktif olmali. Enter'a basin.\n");
	wait_for_enter();
	printf("ACTIVE_SCAN: START channels=1-13 dwell=250ms\n");
	for (uint32_t n = 0; n < WIFI_RF_CHANNEL_COUNT; n++) {
		uint8_t channel = (uint8_t)(n + WIFI_RF_FIRST_CHANNEL);
		struct wifi_rf_metric_delta delta;
		int64_t score;

		current_channel = channel;
		ret = wifi_rf_capture_channel(&ctx, channel,
			WIFI_RF_CAPTURE_ACTIVE, WIFI_RF_SCAN_DWELL_MS,
			&baseline[n], &active[n]);
		if (ret < 0)
			goto channel_fail;
		print_channel(channel, &active[n]);
		delta = wifi_rf_delta(&baseline[n], &active[n]);
		score = activity_score(&delta);
		if (score > best_score) {
			best_score = score;
			selected = n;
			selected_delta = delta;
		}
	}

	current_channel = (uint8_t)(selected + WIFI_RF_FIRST_CHANNEL);
	printf("SELECTED: CH=%02u FREQ=%"PRIu64"MHz DELTA_RSSI=",
	       (unsigned int)current_channel,
	       wifi_rf_channel_frequency_hz(current_channel) / UINT64_C(1000000));
	if (selected_delta.rssi_cdb == WIFI_RF_RSSI_INVALID_CDB)
		printf("ERROR");
	else
		print_centi_db(selected_delta.rssi_cdb);
	printf("dB DELTA_PWR=");
	print_centi_db(selected_delta.power_cdb);
	printf("dB DELTA_BURST=%+"PRIi32"pp\n", selected_delta.burst_pp);
	printf("MONITOR: CH=%02u duration=10s\n", (unsigned int)current_channel);
	total_clip = active[selected].clip_count;
	total_samples = active[selected].complex_samples;

	for (uint32_t n = 0; n < WIFI_RF_MONITOR_WINDOWS; n++) {
		ret = wifi_rf_capture_channel(&ctx, current_channel,
			WIFI_RF_CAPTURE_ACTIVE, WIFI_RF_MONITOR_DWELL_MS,
			&baseline[selected], &monitor);
		if (ret < 0)
			goto channel_fail;
		print_channel(current_channel, &monitor);
		if (monitor.burst_percent > 0U)
			monitor_hits++;
		total_clip += monitor.clip_count;
		total_samples += monitor.complex_samples;
	}

	printf("PLATFORM: PASS\n");
	verdict = classify_activity(&selected_delta, monitor_hits, total_clip,
				    total_samples);
	if (verdict == WIFI_RF_ACTIVITY_PASS) {
		printf("RF_ACTIVITY: PASS\nWIFI_RF_TEST: PASS\n");
		return WIFI_RF_TEST_PASS;
	}
	printf("RF_ACTIVITY: INCONCLUSIVE\nWIFI_RF_TEST: INCONCLUSIVE\n");
	if (clipping_above_limit(total_clip, total_samples))
		printf("WARNING: clipping above 0.1%%; move hotspot farther from RXB.\n");
	else
		printf("WARNING: activity delta too small; verify 2.4 GHz client traffic and move hotspot closer.\n");
	return WIFI_RF_TEST_INCONCLUSIVE;

rx_only_fail:
	printf("PLATFORM: FAIL stage=RX_ONLY error=%"PRIi32"\n", ret);
	return ret;
channel_fail:
	printf("CH=%02u %s code=%"PRIi32"\n", (unsigned int)current_channel,
	       ctx.last_error, ret);
	printf("PLATFORM: FAIL stage=CHANNEL_CAPTURE error=%"PRIi32"\n", ret);
	return ret;
sample_format_fail:
	printf("PLATFORM: FAIL stage=SAMPLE_FORMAT_ERROR error=%"PRIi32"\n", ret);
	return ret;
}
