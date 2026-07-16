$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $root 'Vitis\workspace\ad9364app\src\adc9364_src'
$capture = Join-Path $sourceRoot 'wifi_rf_capture.c'
$header = Join-Path $sourceRoot 'wifi_rf_capture.h'

foreach ($path in @($capture, $header)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Wi-Fi RF capture source: $path"
    }
}

$content = Get-Content -LiteralPath $capture -Raw
$required = @(
    'ad9361_set_rx_rf_port_input(ctx->phy, B_BALANCED)',
    'ad9361_get_rx_rf_port_input(ctx->phy, &port)',
    'ad9361_set_tx_attenuation(ctx->phy, 0, 89750)',
    'ad9361_set_en_state_machine_mode(ctx->phy, ENSM_MODE_RX)',
    'ad9361_get_en_state_machine_mode(ctx->phy, &ensm)',
    '.cyclic = NO',
    'axi_dmac_transfer_wait_completion(ctx->rx_dmac, WIFI_RF_DMA_TIMEOUT_MS)',
    'Xil_DCacheInvalidateRange',
    'RF_GAIN_SLOWATTACK_AGC',
    'RF_GAIN_MGC',
    'ad9361_set_rx_rf_gain',
    'ad9361_get_rx_rssi',
    'wifi_rf_analyze_block',
    'LO_ERROR',
    'GAIN_ERROR',
    'DMA_ERROR'
)
foreach ($fragment in $required) {
    if (-not $content.Contains($fragment)) {
        throw "Capture path is missing required safety/measurement fragment: $fragment"
    }
}

if ($content -match 'axi_dmac_transfer_start\s*\(\s*tx_dmac' -or
    $content -match 'axi_dac_' -or $content -match 'AXI_DAC_DATA_SEL_DDS') {
    throw 'Wi-Fi RF capture path contains TX DAC/DDS/DMAC behavior.'
}

$fallbackGcc = 'C:\MinGW\bin\gcc.exe'
$gccCommand = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue
if ($env:WIFI_RF_GCC) {
    if (-not (Test-Path -LiteralPath $env:WIFI_RF_GCC -PathType Leaf)) {
        throw "Configured GCC executable does not exist: $env:WIFI_RF_GCC"
    }
    $gcc = (Resolve-Path -LiteralPath $env:WIFI_RF_GCC).Path
}
elseif ($gccCommand) {
    $gcc = $gccCommand.Source
}
elseif (Test-Path -LiteralPath $fallbackGcc -PathType Leaf) {
    $gcc = $fallbackGcc
}
else {
    throw 'GCC was not found. Set WIFI_RF_GCC or install MinGW GCC.'
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = [IO.Path]::GetFullPath((Join-Path $tempBase "wifi-rf-capture-$([guid]::NewGuid())"))
if (-not $tempRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe capture-test temporary path: $tempRoot"
}
$stubAd9361 = Join-Path $tempRoot 'ad9361_api.h'
$stubDmac = Join-Path $tempRoot 'axi_dmac.h'
$stubDelay = Join-Path $tempRoot 'no_os_delay.h'
$stubCache = Join-Path $tempRoot 'xil_cache.h'
$harness = Join-Path $tempRoot 'wifi_rf_capture_test.c'
$output = Join-Path $tempRoot 'wifi_rf_capture_test.exe'

$ad9361Header = @'
#ifndef AD9361_API_H
#define AD9361_API_H
#include <stdint.h>
struct ad9361_rf_phy { uint32_t marker; };
struct rf_rssi {
	uint32_t ant;
	uint32_t symbol;
	uint32_t preamble;
	int32_t multiplier;
	uint8_t duration;
};
#define A_BALANCED 0U
#define B_BALANCED 1U
#define ENSM_MODE_RX 1U
#define RF_GAIN_MGC 0U
#define RF_GAIN_SLOWATTACK_AGC 2U
int32_t ad9361_set_rx_rf_port_input(struct ad9361_rf_phy *, uint32_t);
int32_t ad9361_get_rx_rf_port_input(struct ad9361_rf_phy *, uint32_t *);
int32_t ad9361_set_tx_attenuation(struct ad9361_rf_phy *, uint8_t, uint32_t);
int32_t ad9361_set_en_state_machine_mode(struct ad9361_rf_phy *, uint32_t);
int32_t ad9361_get_en_state_machine_mode(struct ad9361_rf_phy *, uint32_t *);
int32_t ad9361_set_rx_lo_freq(struct ad9361_rf_phy *, uint64_t);
int32_t ad9361_set_rx_gain_control_mode(struct ad9361_rf_phy *, uint8_t, uint8_t);
int32_t ad9361_get_rx_rf_gain(struct ad9361_rf_phy *, uint8_t, int32_t *);
int32_t ad9361_set_rx_rf_gain(struct ad9361_rf_phy *, uint8_t, int32_t);
int32_t ad9361_get_rx_rssi(struct ad9361_rf_phy *, uint8_t, struct rf_rssi *);
#endif
'@

$dmacHeader = @'
#ifndef AXI_DMAC_H
#define AXI_DMAC_H
#include <stdbool.h>
#include <stdint.h>
enum cyclic_transfer { NO = 0, CYCLIC = 1 };
struct axi_dma_transfer {
	uint32_t size;
	volatile bool transfer_done;
	enum cyclic_transfer cyclic;
	uint32_t src_addr;
	uint32_t dest_addr;
};
struct axi_dmac {
	volatile struct axi_dma_transfer transfer;
};
int32_t axi_dmac_transfer_start(struct axi_dmac *, struct axi_dma_transfer *);
int32_t axi_dmac_transfer_wait_completion(struct axi_dmac *, uint32_t);
#endif
'@

$delayHeader = @'
#ifndef NO_OS_DELAY_H
#define NO_OS_DELAY_H
#include <stdint.h>
struct no_os_time { unsigned int s, us; };
void no_os_mdelay(uint32_t);
struct no_os_time no_os_get_time(void);
#endif
'@

$cacheHeader = @'
#ifndef XIL_CACHE_H
#define XIL_CACHE_H
#include <stdint.h>
void Xil_DCacheInvalidateRange(uintptr_t, uintptr_t);
#endif
'@

$harnessContent = @'
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "no_os_delay.h"
#include "wifi_rf_capture.h"

#define TEST_TIMEOUT_ERROR (-77)

enum event_id {
	EV_SET_PORT = 1, EV_GET_PORT, EV_SET_TX_ATTEN, EV_SET_ENSM, EV_GET_ENSM,
	EV_SET_LO, EV_SET_AGC, EV_DELAY, EV_GET_GAIN, EV_SET_MGC, EV_SET_GAIN,
	EV_CACHE, EV_DMA_START, EV_DMA_WAIT, EV_ANALYZE, EV_GET_RSSI
};

static int events[128];
static size_t event_count;
static int protocol_errors;
static uint32_t returned_port = B_BALANCED;
static uint32_t returned_ensm = ENSM_MODE_RX;
static int32_t wait_result;
static int32_t analyze_result;
static unsigned time_reads;
static unsigned dma_starts;
static unsigned dma_waits;
static unsigned analyze_calls;
static unsigned cache_calls;
static unsigned stale_done_starts;
static int32_t last_set_gain;
static struct axi_dmac *expected_dmac;
static int16_t *expected_iq;
static size_t expected_samples;

static void record_event(int event)
{
	if (event_count < sizeof(events) / sizeof(events[0]))
		events[event_count++] = event;
	else
		protocol_errors++;
}

static void reset_stubs(void)
{
	memset(events, 0, sizeof(events));
	event_count = 0;
	protocol_errors = 0;
	returned_port = B_BALANCED;
	returned_ensm = ENSM_MODE_RX;
	wait_result = 0;
	analyze_result = 0;
	time_reads = 0;
	dma_starts = 0;
	dma_waits = 0;
	analyze_calls = 0;
	cache_calls = 0;
	stale_done_starts = 0;
	last_set_gain = INT32_MIN;
}

static int fail_check(const char *test, const char *detail, long actual, long expected)
{
	fprintf(stderr, "FAIL: %s: %s (actual=%ld expected=%ld)\n",
		test, detail, actual, expected);
	return 1;
}

#define CHECK_EQ(test, detail, actual, expected) do { \
	long check_actual = (long)(actual); \
	long check_expected = (long)(expected); \
	if (check_actual != check_expected) \
		return fail_check((test), (detail), check_actual, check_expected); \
} while (0)

#define CHECK_TRUE(test, detail, condition) do { \
	if (!(condition)) \
		return fail_check((test), (detail), 0, 1); \
} while (0)

static int check_label(const char *test, const char *actual, const char *expected)
{
	if (actual && strcmp(actual, expected) == 0)
		return 0;
	fprintf(stderr, "FAIL: %s: label (actual=%s expected=%s)\n",
		test, actual ? actual : "NULL", expected);
	return 1;
}

static int check_events(const char *test, const int *expected, size_t count)
{
	size_t n;
	if (event_count != count)
		return fail_check(test, "event count", (long)event_count, (long)count);
	for (n = 0; n < count; n++)
		if (events[n] != expected[n])
			return fail_check(test, "event order", events[n], expected[n]);
	return 0;
}

int32_t ad9361_set_rx_rf_port_input(struct ad9361_rf_phy *phy, uint32_t mode)
{
	record_event(EV_SET_PORT);
	if (!phy || mode != B_BALANCED) protocol_errors++;
	return 0;
}

int32_t ad9361_get_rx_rf_port_input(struct ad9361_rf_phy *phy, uint32_t *mode)
{
	record_event(EV_GET_PORT);
	if (!phy || !mode) protocol_errors++;
	else *mode = returned_port;
	return 0;
}

int32_t ad9361_set_tx_attenuation(struct ad9361_rf_phy *phy, uint8_t ch,
					  uint32_t attenuation)
{
	record_event(EV_SET_TX_ATTEN);
	if (!phy || ch != 0 || attenuation != 89750U) protocol_errors++;
	return 0;
}

int32_t ad9361_set_en_state_machine_mode(struct ad9361_rf_phy *phy,
					 uint32_t mode)
{
	record_event(EV_SET_ENSM);
	if (!phy || mode != ENSM_MODE_RX) protocol_errors++;
	return 0;
}

int32_t ad9361_get_en_state_machine_mode(struct ad9361_rf_phy *phy,
					 uint32_t *mode)
{
	record_event(EV_GET_ENSM);
	if (!phy || !mode) protocol_errors++;
	else *mode = returned_ensm;
	return 0;
}

int32_t ad9361_set_rx_lo_freq(struct ad9361_rf_phy *phy, uint64_t frequency)
{
	record_event(EV_SET_LO);
	if (!phy || frequency != 2412000000ULL) protocol_errors++;
	return 0;
}

int32_t ad9361_set_rx_gain_control_mode(struct ad9361_rf_phy *phy, uint8_t ch,
					uint8_t mode)
{
	if (mode == RF_GAIN_SLOWATTACK_AGC) record_event(EV_SET_AGC);
	else if (mode == RF_GAIN_MGC) record_event(EV_SET_MGC);
	else protocol_errors++;
	if (!phy || ch != 0) protocol_errors++;
	return 0;
}

int32_t ad9361_get_rx_rf_gain(struct ad9361_rf_phy *phy, uint8_t ch,
			     int32_t *gain)
{
	record_event(EV_GET_GAIN);
	if (!phy || ch != 0 || !gain) protocol_errors++;
	else *gain = 23;
	return 0;
}

int32_t ad9361_set_rx_rf_gain(struct ad9361_rf_phy *phy, uint8_t ch,
			     int32_t gain)
{
	record_event(EV_SET_GAIN);
	if (!phy || ch != 0) protocol_errors++;
	last_set_gain = gain;
	return 0;
}

int32_t ad9361_get_rx_rssi(struct ad9361_rf_phy *phy, uint8_t ch,
			   struct rf_rssi *rssi)
{
	record_event(EV_GET_RSSI);
	if (!phy || ch != 0 || !rssi) protocol_errors++;
	else {
		rssi->symbol = 55;
		rssi->multiplier = 1;
	}
	return 0;
}

void no_os_mdelay(uint32_t msecs)
{
	record_event(EV_DELAY);
	if (msecs != WIFI_RF_LO_SETTLE_MS) protocol_errors++;
}

struct no_os_time no_os_get_time(void)
{
	struct no_os_time now = {0, 0};
	if (time_reads++ >= 2U) now.us = 2000U;
	return now;
}

void Xil_DCacheInvalidateRange(uintptr_t address, uintptr_t length)
{
	record_event(EV_CACHE);
	cache_calls++;
	if (address != (uintptr_t)expected_iq ||
	    length != expected_samples * 2U * sizeof(int16_t))
		protocol_errors++;
}

int32_t axi_dmac_transfer_start(struct axi_dmac *dmac,
				struct axi_dma_transfer *transfer)
{
	record_event(EV_DMA_START);
	dma_starts++;
	if (dmac != expected_dmac || !transfer || transfer->cyclic != NO ||
	    transfer->size != expected_samples * 2U * sizeof(int16_t) ||
	    transfer->dest_addr != (uint32_t)(uintptr_t)expected_iq)
		protocol_errors++;
	if (dmac->transfer.transfer_done) stale_done_starts++;
	dmac->transfer.size = transfer->size;
	dmac->transfer.cyclic = transfer->cyclic;
	dmac->transfer.src_addr = transfer->src_addr;
	dmac->transfer.dest_addr = transfer->dest_addr;
	return 0;
}

int32_t axi_dmac_transfer_wait_completion(struct axi_dmac *dmac,
					  uint32_t timeout_ms)
{
	record_event(EV_DMA_WAIT);
	dma_waits++;
	if (dmac != expected_dmac || timeout_ms != WIFI_RF_DMA_TIMEOUT_MS)
		protocol_errors++;
	if (wait_result < 0) return wait_result;
	dmac->transfer.transfer_done = true;
	return 0;
}

int32_t wifi_rf_analyze_block(const int16_t *iq, size_t samples,
			      struct wifi_rf_block_metrics *out)
{
	unsigned index = analyze_calls++;
	record_event(EV_ANALYZE);
	if (iq != expected_iq || samples != expected_samples || !out)
		protocol_errors++;
	if (analyze_result < 0) return analyze_result;
	out->mean_power = index == 0U ? 10U : 50U;
	out->complex_samples = (uint32_t)samples;
	out->clip_count = index == 0U ? 1U : 2U;
	out->peak_abs = index == 0U ? 100U : 200U;
	return 0;
}

uint64_t wifi_rf_median_u64(uint64_t *values, size_t count)
{
	size_t i, j;
	for (i = 1; i < count; i++) {
		uint64_t key = values[i];
		for (j = i; j > 0 && values[j - 1] > key; j--)
			values[j] = values[j - 1];
		values[j] = key;
	}
	return count ? values[count / 2U] : 0U;
}

int32_t wifi_rf_power_cdbfs16(uint64_t mean_power)
{
	return (int32_t)mean_power;
}

int32_t wifi_rf_peak_cdbfs16(uint16_t peak_abs)
{
	return (int32_t)peak_abs;
}

static int test_init_boundaries(void)
{
	const char *test = "init boundaries";
	struct wifi_rf_capture_ctx ctx;
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac;
	size_t aggregate_limit = (size_t)UINT32_MAX / WIFI_RF_MAX_BLOCKS;
	size_t aligned_limit = aggregate_limit & ~(size_t)15U;

	memset(&ctx, 0, sizeof(ctx));
	memset(&dmac, 0, sizeof(dmac));
	ctx.last_error = "OLD";
	CHECK_EQ(test, "null context", wifi_rf_capture_init(NULL, &phy, &dmac,
		(int16_t *)(uintptr_t)0x40U, 16U), -EINVAL);
	CHECK_EQ(test, "null buffer", wifi_rf_capture_init(&ctx, &phy, &dmac,
		NULL, 16U), -EINVAL);
	CHECK_EQ(test, "misaligned address", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)(uintptr_t)0x42U, 16U), -EINVAL);
	CHECK_EQ(test, "zero samples", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)(uintptr_t)0x40U, 0U), -EINVAL);
	CHECK_EQ(test, "aggregate-safe maximum", wifi_rf_capture_init(&ctx, &phy,
		&dmac, (int16_t *)(uintptr_t)0x40U, aligned_limit), 0);
	if (check_label(test, ctx.last_error, "NONE")) return 1;
	CHECK_EQ(test, "aggregate overflow", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)(uintptr_t)0x40U, aligned_limit + 16U), -EINVAL);
	CHECK_EQ(test, "non-cacheline byte count", wifi_rf_capture_init(&ctx, &phy,
		&dmac, (int16_t *)(uintptr_t)0x40U, 15U), -EINVAL);
	CHECK_EQ(test, "last representable byte", wifi_rf_capture_init(&ctx, &phy,
		&dmac, (int16_t *)(uintptr_t)0xFFFFFFC0U, 16U), 0);
	CHECK_EQ(test, "range beyond uint32", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)(uintptr_t)0xFFFFFFC0U, 32U), -EINVAL);
	if (check_label(test, ctx.last_error, "ARG_ERROR")) return 1;
#if UINTPTR_MAX > UINT32_MAX
	CHECK_EQ(test, "high pointer", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)((uintptr_t)UINT32_MAX + 1U), 16U), -EINVAL);
#endif
	CHECK_EQ(test, "valid buffer", wifi_rf_capture_init(&ctx, &phy, &dmac,
		(int16_t *)(uintptr_t)0x40U, 16U), 0);
	CHECK_TRUE(test, "context dependencies",
		ctx.phy == &phy && ctx.rx_dmac == &dmac &&
		ctx.iq_buffer == (int16_t *)(uintptr_t)0x40U &&
		ctx.complex_samples == 16U);
	return 0;
}

static int test_rx_only_safety(void)
{
	const char *test = "RX-only safety";
	const int expected[] = {
		EV_SET_PORT, EV_GET_PORT, EV_SET_TX_ATTEN, EV_SET_ENSM, EV_GET_ENSM
	};
	struct wifi_rf_capture_ctx ctx;
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac;

	memset(&ctx, 0, sizeof(ctx));
	memset(&dmac, 0, sizeof(dmac));
	ctx.phy = &phy;
	ctx.rx_dmac = &dmac;
	ctx.last_error = "OLD";
	reset_stubs();
	CHECK_EQ(test, "valid prepare", wifi_rf_prepare_rx_only(&ctx), 0);
	if (check_label(test, ctx.last_error, "NONE")) return 1;
	CHECK_EQ(test, "protocol", protocol_errors, 0);
	if (check_events(test, expected, sizeof(expected) / sizeof(expected[0]))) return 1;

	reset_stubs();
	returned_port = A_BALANCED;
	CHECK_EQ(test, "port mismatch", wifi_rf_prepare_rx_only(&ctx), -EIO);
	if (check_label(test, ctx.last_error, "RX_ONLY_ERROR")) return 1;
	reset_stubs();
	returned_ensm = 7U;
	CHECK_EQ(test, "ENSM mismatch", wifi_rf_prepare_rx_only(&ctx), -EIO);
	if (check_label(test, ctx.last_error, "RX_ONLY_ERROR")) return 1;
	ctx.phy = NULL;
	CHECK_EQ(test, "missing phy", wifi_rf_prepare_rx_only(&ctx), -EINVAL);
	if (check_label(test, ctx.last_error, "ARG_ERROR")) return 1;
	return 0;
}

static void setup_capture(struct wifi_rf_capture_ctx *ctx,
			  struct ad9361_rf_phy *phy, struct axi_dmac *dmac,
			  int16_t *iq)
{
	memset(ctx, 0, sizeof(*ctx));
	memset(dmac, 0, sizeof(*dmac));
	ctx->phy = phy;
	ctx->rx_dmac = dmac;
	ctx->iq_buffer = iq;
	ctx->complex_samples = 16U;
	ctx->last_error = "OLD";
	expected_dmac = dmac;
	expected_iq = iq;
	expected_samples = 16U;
}

static int test_channel_mapping_and_arguments(void)
{
	const char *test = "channel arguments";
	struct wifi_rf_capture_ctx ctx;
	struct wifi_rf_channel_metrics baseline = {0};
	struct wifi_rf_channel_metrics out;
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac;
	static int16_t iq[32] __attribute__((aligned(64)));
	uint8_t channel;

	for (channel = 1U; channel <= 13U; channel++)
		CHECK_TRUE(test, "channel mapping",
			wifi_rf_channel_frequency_hz(channel) ==
			2412000000ULL + (uint64_t)(channel - 1U) * 5000000ULL);
	CHECK_EQ(test, "channel zero", wifi_rf_channel_frequency_hz(0U), 0);
	CHECK_EQ(test, "channel fourteen", wifi_rf_channel_frequency_hz(14U), 0);
	setup_capture(&ctx, &phy, &dmac, iq);
	reset_stubs();
	CHECK_EQ(test, "invalid mode", wifi_rf_capture_channel(&ctx, 1U,
		(enum wifi_rf_capture_mode)99, 1U, &baseline, &out), -EINVAL);
	if (check_label(test, ctx.last_error, "ARG_ERROR")) return 1;
	CHECK_EQ(test, "invalid mode has no hardware calls", event_count, 0);
	CHECK_EQ(test, "active needs baseline", wifi_rf_capture_channel(&ctx, 1U,
		WIFI_RF_CAPTURE_ACTIVE, 1U, NULL, &out), -EINVAL);
	if (check_label(test, ctx.last_error, "ARG_ERROR")) return 1;
	return 0;
}

static int test_repeated_dma_and_aggregation(void)
{
	const char *test = "repeated DMA";
	const int baseline_events[] = {
		EV_SET_LO, EV_SET_AGC, EV_DELAY, EV_GET_GAIN, EV_SET_MGC, EV_SET_GAIN,
		EV_CACHE, EV_DMA_START, EV_DMA_WAIT, EV_CACHE, EV_ANALYZE,
		EV_CACHE, EV_DMA_START, EV_DMA_WAIT, EV_CACHE, EV_ANALYZE, EV_GET_RSSI
	};
	const int active_events[] = {
		EV_SET_LO, EV_DELAY, EV_SET_MGC, EV_SET_GAIN,
		EV_CACHE, EV_DMA_START, EV_DMA_WAIT, EV_CACHE, EV_ANALYZE,
		EV_CACHE, EV_DMA_START, EV_DMA_WAIT, EV_CACHE, EV_ANALYZE, EV_GET_RSSI
	};
	struct wifi_rf_capture_ctx ctx;
	struct wifi_rf_channel_metrics baseline;
	struct wifi_rf_channel_metrics out;
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac;
	static int16_t iq[32] __attribute__((aligned(64)));

	setup_capture(&ctx, &phy, &dmac, iq);
	reset_stubs();
	dmac.transfer.transfer_done = true;
	CHECK_EQ(test, "baseline capture", wifi_rf_capture_channel(&ctx, 1U,
		WIFI_RF_CAPTURE_BASELINE, 1U, NULL, &baseline), 0);
	if (check_label(test, ctx.last_error, "NONE")) return 1;
	CHECK_EQ(test, "stale flag reset", stale_done_starts, 0);
	CHECK_EQ(test, "two starts", dma_starts, 2);
	CHECK_EQ(test, "two waits", dma_waits, 2);
	CHECK_EQ(test, "pre/post cache ownership", cache_calls, 4);
	CHECK_EQ(test, "analyze count", analyze_calls, 2);
	CHECK_EQ(test, "protocol", protocol_errors, 0);
	CHECK_EQ(test, "blocks", baseline.dma_blocks, 2);
	CHECK_EQ(test, "samples", baseline.complex_samples, 32);
	CHECK_EQ(test, "clips", baseline.clip_count, 3);
	CHECK_EQ(test, "mean power", baseline.power_cdbfs16, 30);
	CHECK_EQ(test, "peak", baseline.peak_cdbfs16, 200);
	CHECK_EQ(test, "gain", baseline.gain_db, 23);
	CHECK_EQ(test, "median", baseline.baseline_median_power, 50);
	CHECK_EQ(test, "baseline bursts", baseline.burst_percent, 0);
	CHECK_EQ(test, "RSSI", baseline.rssi_cdb, -5500);
	if (check_events(test, baseline_events,
		sizeof(baseline_events) / sizeof(baseline_events[0]))) return 1;

	setup_capture(&ctx, &phy, &dmac, iq);
	reset_stubs();
	baseline.gain_db = 17;
	baseline.baseline_median_power = 10U;
	CHECK_EQ(test, "active capture", wifi_rf_capture_channel(&ctx, 1U,
		WIFI_RF_CAPTURE_ACTIVE, 1U, &baseline, &out), 0);
	CHECK_EQ(test, "baseline gain reused", last_set_gain, 17);
	CHECK_EQ(test, "active baseline reused", out.baseline_median_power, 10);
	CHECK_EQ(test, "active bursts", out.burst_percent, 50);
	CHECK_EQ(test, "active protocol", protocol_errors, 0);
	if (check_events(test, active_events,
		sizeof(active_events) / sizeof(active_events[0]))) return 1;
	return 0;
}

static int test_failure_labels(void)
{
	const char *test = "failure labels";
	struct wifi_rf_capture_ctx ctx;
	struct wifi_rf_channel_metrics baseline = {.gain_db = 17,
		.baseline_median_power = 10U};
	struct wifi_rf_channel_metrics out;
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac;
	static int16_t iq[32] __attribute__((aligned(64)));

	setup_capture(&ctx, &phy, &dmac, iq);
	reset_stubs();
	dmac.transfer.transfer_done = true;
	wait_result = TEST_TIMEOUT_ERROR;
	CHECK_EQ(test, "DMA timeout", wifi_rf_capture_channel(&ctx, 1U,
		WIFI_RF_CAPTURE_ACTIVE, 1U, &baseline, &out), TEST_TIMEOUT_ERROR);
	if (check_label(test, ctx.last_error, "DMA_ERROR")) return 1;
	CHECK_EQ(test, "timeout flag reset", stale_done_starts, 0);
	CHECK_EQ(test, "timeout pre-invalidate", cache_calls, 1);
	CHECK_EQ(test, "timeout not analyzed", analyze_calls, 0);

	setup_capture(&ctx, &phy, &dmac, iq);
	reset_stubs();
	analyze_result = -EIO;
	CHECK_EQ(test, "analysis failure", wifi_rf_capture_channel(&ctx, 1U,
		WIFI_RF_CAPTURE_ACTIVE, 1U, &baseline, &out), -EIO);
	if (check_label(test, ctx.last_error, "ANALYZE_ERROR")) return 1;
	CHECK_EQ(test, "analysis post-invalidate", cache_calls, 2);
	return 0;
}

int main(void)
{
	if (test_init_boundaries()) return 1;
	if (test_rx_only_safety()) return 1;
	if (test_channel_mapping_and_arguments()) return 1;
	if (test_repeated_dma_and_aggregation()) return 1;
	if (test_failure_labels()) return 1;
	puts("PASS: Wi-Fi RF capture host behavior passed.");
	return 0;
}
'@

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Set-Content -LiteralPath $stubAd9361 -Value $ad9361Header -Encoding Ascii
    Set-Content -LiteralPath $stubDmac -Value $dmacHeader -Encoding Ascii
    Set-Content -LiteralPath $stubDelay -Value $delayHeader -Encoding Ascii
    Set-Content -LiteralPath $stubCache -Value $cacheHeader -Encoding Ascii
    Set-Content -LiteralPath $harness -Value $harnessContent -Encoding Ascii
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$tempRoot" "-I$sourceRoot" `
        $harness $capture -o $output
    if ($LASTEXITCODE -ne 0) { throw "Native capture compilation failed with: $gcc" }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Native capture behavior test failed.' }
}
finally {
    if ((Test-Path -LiteralPath $tempRoot) -and
        ([IO.Path]::GetFullPath($tempRoot)).StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$structural = @(
    'ctx->rx_dmac->transfer.transfer_done = false',
    'addr > UINT32_MAX',
    'bytes - 1U',
    'UINT32_MAX - (uint32_t)addr',
    'complex_samples > UINT32_MAX / WIFI_RF_MAX_BLOCKS',
    'bytes & (WIFI_RF_CACHE_LINE_BYTES - 1U)',
    'ARG_ERROR',
    'ANALYZE_ERROR'
)
foreach ($fragment in $structural) {
    if (-not $content.Contains($fragment)) {
        throw "Capture path is missing hardened invariant: $fragment"
    }
}

$dmaSequence = '(?s)Xil_DCacheInvalidateRange\([^;]+;\s*ctx->rx_dmac->transfer\.transfer_done\s*=\s*false;\s*ret\s*=\s*axi_dmac_transfer_start\(ctx->rx_dmac,\s*&transfer\);\s*if\s*\(ret\s*<\s*0\)\s*return\s+ret;\s*ret\s*=\s*axi_dmac_transfer_wait_completion\(ctx->rx_dmac,\s*WIFI_RF_DMA_TIMEOUT_MS\);\s*if\s*\(ret\s*<\s*0\)\s*return\s+ret;\s*Xil_DCacheInvalidateRange\([^;]+;(?s).*wifi_rf_analyze_block'
if ($content -notmatch $dmaSequence) {
    throw 'Capture DMA order must be pre-invalidate, reset done, start, wait, post-invalidate, analyze.'
}
if (([regex]::Matches($content, 'axi_dmac_transfer_start\s*\(')).Count -ne 1 -or
    $content -notmatch 'mode\s*!=\s*WIFI_RF_CAPTURE_BASELINE\s*&&\s*mode\s*!=\s*WIFI_RF_CAPTURE_ACTIVE') {
    throw 'Capture source has an unexpected DMA start site or incomplete mode validation.'
}

$testSource = Join-Path $sourceRoot 'wifi_rf_test.c'
$testHeader = Join-Path $sourceRoot 'wifi_rf_test.h'
foreach ($path in @($testSource, $testHeader)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Wi-Fi RF test state machine: $path"
    }
}
$testContent = Get-Content -LiteralPath $testSource -Raw
foreach ($fragment in @(
    'Hotspot kapali',
    'Hotspot 2.4 GHz',
    'BASELINE_SCAN: START',
    'ACTIVE_SCAN: START',
    'SELECTED:',
    'MONITOR:',
    'PLATFORM: PASS',
    'RF_ACTIVITY: PASS',
    'RF_ACTIVITY: INCONCLUSIVE',
    'WIFI_RF_TEST: PASS',
    'WIFI_RF_TEST: INCONCLUSIVE',
    'XUartPs_IsReceiveData(STDIN_BASEADDRESS)',
    'WIFI_RF_MONITOR_WINDOWS'
)) {
    if (-not $testContent.Contains($fragment)) {
        throw "UART state machine is missing required fragment: $fragment"
    }
}

$stateTempRoot = [IO.Path]::GetFullPath((Join-Path $tempBase "wifi-rf-state-$([guid]::NewGuid())"))
if (-not $stateTempRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe state-machine-test temporary path: $stateTempRoot"
}
$stateStubCapture = Join-Path $stateTempRoot 'wifi_rf_capture.h'
$stateStubMetrics = Join-Path $stateTempRoot 'wifi_rf_metrics.h'
$stateStubAd9361 = Join-Path $stateTempRoot 'ad9361_api.h'
$stateStubDmac = Join-Path $stateTempRoot 'axi_dmac.h'
$stateStubDelay = Join-Path $stateTempRoot 'no_os_delay.h'
$stateStubPrintf = Join-Path $stateTempRoot 'xil_printf.h'
$stateStubParameters = Join-Path $stateTempRoot 'xparameters.h'
$stateStubUart = Join-Path $stateTempRoot 'xuartps_hw.h'
$stateHarness = Join-Path $stateTempRoot 'wifi_rf_test_host.c'
$stateOutput = Join-Path $stateTempRoot 'wifi_rf_test_host.exe'

$stateCaptureHeader = @'
#ifndef WIFI_RF_CAPTURE_H
#define WIFI_RF_CAPTURE_H
#include <stddef.h>
#include <stdint.h>
#include "wifi_rf_metrics.h"
struct ad9361_rf_phy { uint32_t marker; };
struct axi_dmac { uint32_t marker; };
#define WIFI_RF_FIRST_CHANNEL 1U
#define WIFI_RF_CHANNEL_COUNT 13U
#define WIFI_RF_SCAN_DWELL_MS 250U
#define WIFI_RF_MONITOR_DWELL_MS 500U
enum wifi_rf_capture_mode {
	WIFI_RF_CAPTURE_BASELINE = 0,
	WIFI_RF_CAPTURE_ACTIVE = 1
};
struct wifi_rf_capture_ctx {
	struct ad9361_rf_phy *phy;
	struct axi_dmac *rx_dmac;
	int16_t *iq_buffer;
	size_t complex_samples;
	const char *last_error;
};
int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *,
	struct ad9361_rf_phy *, struct axi_dmac *, int16_t *, size_t);
int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *);
uint64_t wifi_rf_channel_frequency_hz(uint8_t);
int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *, uint8_t,
	enum wifi_rf_capture_mode, uint32_t,
	const struct wifi_rf_channel_metrics *, struct wifi_rf_channel_metrics *);
#endif
'@

$stateMetricsHeader = @'
#ifndef WIFI_RF_METRICS_H
#define WIFI_RF_METRICS_H
#include <limits.h>
#include <stdint.h>
#define WIFI_RF_ZERO_CDBFS INT32_MIN
#define WIFI_RF_RSSI_INVALID_CDB INT32_MIN
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
struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *,
	const struct wifi_rf_channel_metrics *);
enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *, uint32_t, uint32_t, uint32_t);
#endif
'@

$stateAd9361Header = @'
#ifndef AD9361_API_H
#define AD9361_API_H
#include <stdint.h>
struct ad9361_rf_phy { uint32_t marker; };
#endif
'@

$stateDmacHeader = @'
#ifndef AXI_DMAC_H
#define AXI_DMAC_H
#include <stdint.h>
struct axi_dmac { uint32_t marker; };
#endif
'@

$stateDelayHeader = @'
#ifndef NO_OS_DELAY_H
#define NO_OS_DELAY_H
#include <stdint.h>
void no_os_mdelay(uint32_t);
#endif
'@

$statePrintfHeader = @'
#ifndef XIL_PRINTF_H
#define XIL_PRINTF_H
int inbyte(void);
#endif
'@

$stateParametersHeader = @'
#ifndef XPARAMETERS_H
#define XPARAMETERS_H
#define STDIN_BASEADDRESS 0U
#endif
'@

$stateUartHeader = @'
#ifndef XUARTPS_HW_H
#define XUARTPS_HW_H
#include <stdint.h>
int XUartPs_IsReceiveData(uintptr_t);
#endif
'@

$stateHarnessContent = @'
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "wifi_rf_capture.h"
#include "wifi_rf_test.h"

enum scenario_id {
	SC_PASS,
	SC_LARGE_COUNTS,
	SC_INCONCLUSIVE,
	SC_CLIPPING,
	SC_INIT_FAIL,
	SC_RX_FAIL,
	SC_CAPTURE_FAIL
};

static enum scenario_id scenario;
static unsigned init_calls;
static unsigned prepare_calls;
static unsigned capture_calls;
static unsigned classify_calls;
static unsigned protocol_errors;
static unsigned enter_delays;

static void reset_scenario(enum scenario_id next)
{
	scenario = next;
	init_calls = 0;
	prepare_calls = 0;
	capture_calls = 0;
	classify_calls = 0;
	protocol_errors = 0;
	enter_delays = 0;
}

static int fail_check(const char *test, const char *detail,
	long actual, long expected)
{
	fprintf(stderr, "FAIL: %s: %s (actual=%ld expected=%ld)\n",
		test, detail, actual, expected);
	return 1;
}

#define CHECK_EQ(test, detail, actual, expected) do { \
	long check_actual = (long)(actual); \
	long check_expected = (long)(expected); \
	if (check_actual != check_expected) \
		return fail_check((test), (detail), check_actual, check_expected); \
} while (0)

int inbyte(void)
{
	return '\n';
}

int XUartPs_IsReceiveData(uintptr_t address)
{
	if (address != 0U) protocol_errors++;
	return 0;
}

void no_os_mdelay(uint32_t msecs)
{
	if (msecs != 20U) protocol_errors++;
	enter_delays++;
}

int32_t wifi_rf_capture_init(struct wifi_rf_capture_ctx *ctx,
	struct ad9361_rf_phy *phy, struct axi_dmac *dmac,
	int16_t *iq_buffer, size_t complex_samples)
{
	init_calls++;
	if (!ctx || !phy || !dmac || !iq_buffer || complex_samples != 16U)
		protocol_errors++;
	if (scenario == SC_INIT_FAIL)
		return -11;
	ctx->phy = phy;
	ctx->rx_dmac = dmac;
	ctx->iq_buffer = iq_buffer;
	ctx->complex_samples = complex_samples;
	ctx->last_error = "NONE";
	return 0;
}

int32_t wifi_rf_prepare_rx_only(struct wifi_rf_capture_ctx *ctx)
{
	prepare_calls++;
	if (!ctx || !ctx->phy || !ctx->rx_dmac) protocol_errors++;
	if (scenario == SC_RX_FAIL) return -12;
	return 0;
}

uint64_t wifi_rf_channel_frequency_hz(uint8_t channel)
{
	if (channel < 1U || channel > 13U) {
		protocol_errors++;
		return 0;
	}
	return 2412000000ULL + (uint64_t)(channel - 1U) * 5000000ULL;
}

static void fill_metrics(struct wifi_rf_channel_metrics *out,
	uint8_t channel, int active, int monitor)
{
	memset(out, 0, sizeof(*out));
	out->gain_db = 23;
	out->rssi_cdb = -6000;
	out->power_cdbfs16 = -3000;
	out->peak_cdbfs16 = WIFI_RF_ZERO_CDBFS;
	out->dma_blocks = 2U;
	out->complex_samples = 1000U;
	if (scenario == SC_LARGE_COUNTS)
		out->complex_samples = UINT32_MAX;
	if (active && (channel == 6U || channel == 7U)) {
		out->rssi_cdb = -5500;
		out->power_cdbfs16 = -2500;
		out->burst_percent = 5U;
	}
	if (monitor) out->burst_percent = 1U;
	if (scenario == SC_CLIPPING && (active || monitor))
		out->clip_count = 2U;
	else if (active || monitor)
		out->clip_count = 1U;
}

int32_t wifi_rf_capture_channel(struct wifi_rf_capture_ctx *ctx,
	uint8_t channel, enum wifi_rf_capture_mode mode, uint32_t dwell_ms,
	const struct wifi_rf_channel_metrics *baseline,
	struct wifi_rf_channel_metrics *out)
{
	unsigned call = capture_calls++;
	if (!ctx || !out) protocol_errors++;
	if (call < 13U) {
		if (channel != call + 1U || mode != WIFI_RF_CAPTURE_BASELINE ||
		    dwell_ms != WIFI_RF_SCAN_DWELL_MS || baseline != NULL)
			protocol_errors++;
		fill_metrics(out, channel, 0, 0);
		return 0;
	}
	if (call < 26U) {
		if (channel != call - 12U || mode != WIFI_RF_CAPTURE_ACTIVE ||
		    dwell_ms != WIFI_RF_SCAN_DWELL_MS || !baseline)
			protocol_errors++;
		if (scenario == SC_CAPTURE_FAIL && channel == 4U) {
			ctx->last_error = "DMA_ERROR";
			return -33;
		}
		fill_metrics(out, channel, 1, 0);
		return 0;
	}
	if (channel != 6U || mode != WIFI_RF_CAPTURE_ACTIVE ||
	    dwell_ms != WIFI_RF_MONITOR_DWELL_MS || !baseline)
		protocol_errors++;
	fill_metrics(out, channel, 1, 1);
	return 0;
}

struct wifi_rf_metric_delta wifi_rf_delta(
	const struct wifi_rf_channel_metrics *baseline,
	const struct wifi_rf_channel_metrics *active)
{
	struct wifi_rf_metric_delta delta = {0};
	if (!baseline || !active) {
		protocol_errors++;
		return delta;
	}
	delta.rssi_cdb = active->rssi_cdb - baseline->rssi_cdb;
	delta.power_cdb = active->power_cdbfs16 - baseline->power_cdbfs16;
	delta.burst_pp = (int32_t)active->burst_percent -
		(int32_t)baseline->burst_percent;
	return delta;
}

enum wifi_rf_activity_verdict wifi_rf_classify(
	const struct wifi_rf_metric_delta *delta, uint32_t monitor_hits,
	uint32_t clip_count, uint32_t complex_samples)
{
	classify_calls++;
	if (!delta || delta->rssi_cdb != 500 || delta->power_cdb != 500 ||
	    delta->burst_pp != 5 || monitor_hits != 20U)
		protocol_errors++;
	if (!((clip_count == 21U && complex_samples == 21000U) ||
	      (clip_count == 0U && complex_samples == 1U)))
		protocol_errors++;
	return scenario == SC_PASS || scenario == SC_LARGE_COUNTS ?
		WIFI_RF_ACTIVITY_PASS :
		WIFI_RF_ACTIVITY_INCONCLUSIVE;
}

static int run_complete_case(const char *test, enum scenario_id next,
	int32_t expected, unsigned expected_classify)
{
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac = {0};
	static int16_t iq[32];
	int32_t result;

	reset_scenario(next);
	result = wifi_rf_test_run(&phy, &dmac, iq, 16U);
	CHECK_EQ(test, "return", result, expected);
	CHECK_EQ(test, "init calls", init_calls, 1U);
	CHECK_EQ(test, "prepare calls", prepare_calls, 1U);
	CHECK_EQ(test, "capture calls", capture_calls, 46U);
	CHECK_EQ(test, "classifier calls", classify_calls, expected_classify);
	CHECK_EQ(test, "prompt delays", enter_delays, 2U);
	CHECK_EQ(test, "protocol", protocol_errors, 0U);
	return 0;
}

static int test_platform_failures(void)
{
	const char *test = "platform failures";
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac = {0};
	static int16_t iq[32];

	reset_scenario(SC_INIT_FAIL);
	CHECK_EQ(test, "sample format return",
		wifi_rf_test_run(&phy, &dmac, iq, 16U), -11);
	CHECK_EQ(test, "sample format stops", prepare_calls, 0U);
	CHECK_EQ(test, "sample format captures", capture_calls, 0U);

	reset_scenario(SC_RX_FAIL);
	CHECK_EQ(test, "RX-only return",
		wifi_rf_test_run(&phy, &dmac, iq, 16U), -12);
	CHECK_EQ(test, "RX-only stops", capture_calls, 0U);

	reset_scenario(SC_CAPTURE_FAIL);
	CHECK_EQ(test, "channel return",
		wifi_rf_test_run(&phy, &dmac, iq, 16U), -33);
	CHECK_EQ(test, "channel stops", capture_calls, 17U);
	CHECK_EQ(test, "failure protocol", protocol_errors, 0U);
	return 0;
}

int main(void)
{
	if (!freopen("NUL", "w", stdout)) return 1;
	if (run_complete_case("PASS verdict", SC_PASS,
		WIFI_RF_TEST_PASS, 1U)) return 1;
	if (run_complete_case("large count verdict", SC_LARGE_COUNTS,
		WIFI_RF_TEST_PASS, 1U)) return 1;
	if (run_complete_case("inconclusive verdict", SC_INCONCLUSIVE,
		WIFI_RF_TEST_INCONCLUSIVE, 1U)) return 1;
	if (run_complete_case("clipping verdict", SC_CLIPPING,
		WIFI_RF_TEST_INCONCLUSIVE, 0U)) return 1;
	if (test_platform_failures()) return 1;
	puts("PASS: Wi-Fi RF state-machine host behavior passed.");
	return 0;
}
'@

try {
    New-Item -ItemType Directory -Path $stateTempRoot | Out-Null
    Set-Content -LiteralPath $stateStubCapture -Value $stateCaptureHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubMetrics -Value $stateMetricsHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubAd9361 -Value $stateAd9361Header -Encoding Ascii
    Set-Content -LiteralPath $stateStubDmac -Value $stateDmacHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubDelay -Value $stateDelayHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubPrintf -Value $statePrintfHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubParameters -Value $stateParametersHeader -Encoding Ascii
    Set-Content -LiteralPath $stateStubUart -Value $stateUartHeader -Encoding Ascii
    Set-Content -LiteralPath $stateHarness -Value $stateHarnessContent -Encoding Ascii
    & $gcc -std=c11 -Wall -Wextra -Werror "-I$stateTempRoot" "-I$sourceRoot" `
        $stateHarness $testSource -o $stateOutput
    if ($LASTEXITCODE -ne 0) { throw "Native state-machine compilation failed with: $gcc" }
    & $stateOutput
    if ($LASTEXITCODE -ne 0) { throw 'Native state-machine behavior test failed.' }
}
finally {
    if ((Test-Path -LiteralPath $stateTempRoot) -and
        ([IO.Path]::GetFullPath($stateTempRoot)).StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $stateTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: Wi-Fi RF capture and UART state-machine source/host behavior passed.'
