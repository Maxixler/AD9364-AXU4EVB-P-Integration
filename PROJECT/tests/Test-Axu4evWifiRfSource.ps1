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
typedef char char8;
extern char8 inbyte(void);
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
typedef uint32_t u32;
typedef uintptr_t UINTPTR;
#define XUARTPS_SR_OFFSET 0x002CU
#define XUARTPS_SR_RXEMPTY 0x00000002U
u32 Xil_In32(UINTPTR address);
#define XUartPs_IsReceiveData(BaseAddress) \
	!((Xil_In32((UINTPTR)(BaseAddress) + XUARTPS_SR_OFFSET) & \
	(u32)XUARTPS_SR_RXEMPTY) == (u32)XUARTPS_SR_RXEMPTY)
#endif
'@

$stateHarnessContent = @'
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "wifi_rf_capture.h"
#include "wifi_rf_test.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"

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
static unsigned uart_prompt_batches;
static unsigned uart_inbyte_calls;
static unsigned uart_status_reads;
static unsigned uart_fifo_position;
static unsigned uart_fifo_count;
static const char8 uart_prompt_input[] = {'\r', '\n', 'x'};
static const struct wifi_rf_channel_metrics *baseline_outputs[13];

static void reset_scenario(enum scenario_id next)
{
	scenario = next;
	init_calls = 0;
	prepare_calls = 0;
	capture_calls = 0;
	classify_calls = 0;
	protocol_errors = 0;
	enter_delays = 0;
	uart_prompt_batches = 0;
	uart_inbyte_calls = 0;
	uart_status_reads = 0;
	uart_fifo_position = 0;
	uart_fifo_count = 0;
	memset(baseline_outputs, 0, sizeof(baseline_outputs));
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

char8 inbyte(void)
{
	if (uart_fifo_position == uart_fifo_count) {
		if (uart_prompt_batches >= 2U) {
			protocol_errors++;
			return '\n';
		}
		uart_prompt_batches++;
		uart_fifo_position = 0;
		uart_fifo_count = sizeof(uart_prompt_input) /
			sizeof(uart_prompt_input[0]);
	}
	uart_inbyte_calls++;
	return uart_prompt_input[uart_fifo_position++];
}

u32 Xil_In32(UINTPTR address)
{
	uart_status_reads++;
	if (address != (UINTPTR)STDIN_BASEADDRESS + XUARTPS_SR_OFFSET)
		protocol_errors++;
	return uart_fifo_position < uart_fifo_count ? 0U : XUARTPS_SR_RXEMPTY;
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
	out->gain_db = active ? 23 : 20 + channel;
	out->baseline_median_power = 1000U + channel;
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
		baseline_outputs[channel - 1U] = out;
		fill_metrics(out, channel, 0, 0);
		return 0;
	}
	if (call < 26U) {
		if (channel != call - 12U || mode != WIFI_RF_CAPTURE_ACTIVE ||
		    dwell_ms != WIFI_RF_SCAN_DWELL_MS ||
		    baseline != baseline_outputs[channel - 1U] ||
		    baseline->gain_db != 20 + channel ||
		    baseline->baseline_median_power != 1000U + channel)
			protocol_errors++;
		if (scenario == SC_CAPTURE_FAIL && channel == 4U) {
			ctx->last_error = "DMA_ERROR";
			return -33;
		}
		fill_metrics(out, channel, 1, 0);
		return 0;
	}
	if (channel != 6U || mode != WIFI_RF_CAPTURE_ACTIVE ||
	    dwell_ms != WIFI_RF_MONITOR_DWELL_MS ||
	    baseline != baseline_outputs[5] ||
	    baseline->gain_db != 26 ||
	    baseline->baseline_median_power != 1006U)
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
	printf("HOST_CASE: %s\n", test);
	result = wifi_rf_test_run(&phy, &dmac, iq, 16U);
	CHECK_EQ(test, "return", result, expected);
	CHECK_EQ(test, "init calls", init_calls, 1U);
	CHECK_EQ(test, "prepare calls", prepare_calls, 1U);
	CHECK_EQ(test, "capture calls", capture_calls, 46U);
	CHECK_EQ(test, "classifier calls", classify_calls, expected_classify);
	CHECK_EQ(test, "prompt delays", enter_delays, 2U);
	CHECK_EQ(test, "CRLF prompt batches", uart_prompt_batches, 2U);
	CHECK_EQ(test, "CRLF and queued bytes consumed", uart_inbyte_calls, 6U);
	CHECK_EQ(test, "queued-drain status reads", uart_status_reads, 6U);
	CHECK_EQ(test, "protocol", protocol_errors, 0U);
	return 0;
}

static int test_platform_failures(void)
{
	const char *test = "platform failures";
	struct ad9361_rf_phy phy = {0};
	struct axi_dmac dmac = {0};
	static int16_t iq[32];

	puts("HOST_CASE: platform failures");
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
    $stateHostOutput = @(& $stateOutput)
    if ($LASTEXITCODE -ne 0) { throw 'Native state-machine behavior test failed.' }

    function Get-ExactLineIndex([string[]]$Lines, [string]$Expected) {
        for ($n = 0; $n -lt $Lines.Count; $n++) {
            if ($Lines[$n] -ceq $Expected) { return $n }
        }
        return -1
    }

    function Get-StateCaseLines([string[]]$Lines, [string]$Label, [string]$NextLabel) {
        $start = Get-ExactLineIndex $Lines "HOST_CASE: $Label"
        if ($start -lt 0) { throw "Native state-machine output is missing case marker: $Label" }
        $end = $Lines.Count
        if ($NextLabel) {
            $end = Get-ExactLineIndex $Lines "HOST_CASE: $NextLabel"
            if ($end -le $start) { throw "Native state-machine case order is invalid: $Label" }
        }
        if ($end -eq $start + 1) { return @() }
        return @($Lines[($start + 1)..($end - 1)])
    }

    function Assert-StateLineOrder([string[]]$Lines, [string[]]$Expected) {
        $previous = -1
        foreach ($line in $Expected) {
            $index = Get-ExactLineIndex $Lines $line
            if ($index -lt 0) { throw "Native state-machine UART output is missing exact line: $line" }
            if ($index -le $previous) { throw "Native state-machine UART line is out of order: $line" }
            $previous = $index
        }
    }

    $passLines = Get-StateCaseLines $stateHostOutput 'PASS verdict' 'large count verdict'
    $baselineLine = 'BASELINE_SCAN: START channels=1-13 dwell=250ms'
    $activeLine = 'ACTIVE_SCAN: START channels=1-13 dwell=250ms'
    $selectedLine = 'SELECTED: CH=06 FREQ=2437MHz DELTA_RSSI=+5.00dB DELTA_PWR=+5.00dB DELTA_BURST=+5pp'
    $monitorLine = 'MONITOR: CH=06 duration=10s'
    $platformLine = 'PLATFORM: PASS'
    $rfPassLine = 'RF_ACTIVITY: PASS'
    $testPassLine = 'WIFI_RF_TEST: PASS'
    Assert-StateLineOrder $passLines @(
        $baselineLine, $activeLine, $selectedLine, $monitorLine,
        $platformLine, $rfPassLine, $testPassLine
    )
    $infLine = 'CH=01 FREQ=2412MHz GAIN=21dB RSSI=-60.00dB PWR=-30.00dBFS16 PEAK=-INFdBFS16 CLIP=0 BURST=0% BLOCKS=2 DMA=OK'
    if ((Get-ExactLineIndex $passLines $infLine) -lt 0) {
        throw 'Native state-machine UART output does not preserve exact -INF formatting.'
    }
    if (@($passLines | Where-Object { $_ -ceq $monitorLine }).Count -ne 1) {
        throw 'Native state-machine UART output must contain one monitor marker.'
    }
    $monitorStart = Get-ExactLineIndex $passLines $monitorLine
    $platformStart = Get-ExactLineIndex $passLines $platformLine
    $monitorWindows = @($passLines[($monitorStart + 1)..($platformStart - 1)])
    if ($monitorWindows.Count -ne 20 -or
        @($monitorWindows | Where-Object { -not $_.StartsWith('CH=06 ') }).Count -ne 0) {
        throw 'Native state-machine UART output must contain 20 selected-channel monitor windows.'
    }

    $inconclusiveLines = Get-StateCaseLines $stateHostOutput 'inconclusive verdict' 'clipping verdict'
    Assert-StateLineOrder $inconclusiveLines @(
        $platformLine,
        'RF_ACTIVITY: INCONCLUSIVE',
        'WIFI_RF_TEST: INCONCLUSIVE',
        'WARNING: activity delta too small; verify 2.4 GHz client traffic and move hotspot closer.'
    )

    $clippingLines = Get-StateCaseLines $stateHostOutput 'clipping verdict' 'platform failures'
    Assert-StateLineOrder $clippingLines @(
        $platformLine,
        'RF_ACTIVITY: INCONCLUSIVE',
        'WIFI_RF_TEST: INCONCLUSIVE',
        'WARNING: clipping above 0.1%; move hotspot farther from RXB.'
    )
    if ($stateHostOutput -notcontains 'PASS: Wi-Fi RF state-machine host behavior passed.') {
        throw 'Native state-machine host harness did not report PASS.'
    }
}
finally {
    if ((Test-Path -LiteralPath $stateTempRoot) -and
        ([IO.Path]::GetFullPath($stateTempRoot)).StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $stateTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$config = Get-Content -LiteralPath (Join-Path $sourceRoot 'app_config.h') -Raw
$main = Get-Content -LiteralPath (Join-Path $sourceRoot 'main.c') -Raw
$cprojectPath = Join-Path $root 'Vitis\workspace\ad9364app\.cproject'
[xml]$cproject = Get-Content -LiteralPath $cprojectPath

foreach ($fragment in @(
    '#define WIFI_RF_TEST',
    '#if defined(WIFI_RF_TEST) && defined(DMA_EXAMPLE)',
    '#error "WIFI_RF_TEST and DMA_EXAMPLE cannot be enabled together"'
)) {
    if (-not $config.Contains($fragment)) { throw "Missing app config invariant: $fragment" }
}
foreach ($fragment in @(
    '#include "wifi_rf_test.h"',
    'status = ad9361_init(&ad9361_phy, &default_init_param);',
    '#ifndef WIFI_RF_TEST',
    'status = wifi_rf_test_run(ad9361_phy, rx_dmac,',
    'goto cleanup;',
    'cleanup:'
)) {
    if (-not $main.Contains($fragment)) { throw "Missing main integration fragment: $fragment" }
}

$mainLines = @($main -split "`r?`n")
$guards = New-Object System.Collections.Generic.List[object]
$stack = New-Object System.Collections.Generic.List[string]
for ($lineIndex = 0; $lineIndex -lt $mainLines.Count; $lineIndex++) {
    $line = $mainLines[$lineIndex]
    if ($line -match '^\s*#\s*(if|ifdef|ifndef)\s+(.+?)\s*$') {
        $stack.Add("$($matches[1]) $($matches[2])")
    }
    $guards.Add(@($stack))
    if ($line -match '^\s*#\s*endif\b') {
        if ($stack.Count -eq 0) { throw "Unbalanced #endif at main.c:$($lineIndex + 1)" }
        $stack.RemoveAt($stack.Count - 1)
    }
}
if ($stack.Count -ne 0) { throw 'Unbalanced preprocessor guards in main.c.' }

function Assert-MainGuard([string]$Needle, [string]$ExpectedGuard, [bool]$ShouldContain) {
    $indexes = @(0..($mainLines.Count - 1) | Where-Object { $mainLines[$_].Contains($Needle) })
    if ($indexes.Count -lt 1) { throw "Missing main.c line containing '$Needle'." }
    $index = $indexes[0]
    $hasGuard = @($guards[$index] | Where-Object { $_ -eq $ExpectedGuard }).Count -gt 0
    if ($hasGuard -ne $ShouldContain) {
        throw "Unexpected guard structure for '$Needle': $($guards[$index] -join ', ')"
    }
    return $indexes[0]
}

$txInitLine = Assert-MainGuard 'status = axi_dmac_init(&tx_dmac' 'ifndef WIFI_RF_TEST' $true
$rxInitLine = Assert-MainGuard 'status = axi_dmac_init(&rx_dmac' 'ifndef WIFI_RF_TEST' $false
$wifiRunLine = Assert-MainGuard 'status = wifi_rf_test_run(ad9361_phy' 'ifdef WIFI_RF_TEST' $true
$normalFlowLine = Assert-MainGuard 'axi_dmac_transfer_start(tx_dmac' 'ifdef WIFI_RF_TEST' $false
if (-not ($txInitLine -lt $rxInitLine -and $rxInitLine -lt $wifiRunLine -and
    $wifiRunLine -lt $normalFlowLine)) {
    throw 'AD9364 main integration order is invalid.'
}

$configurations = @($cproject.SelectNodes('//cconfiguration'))
foreach ($configurationName in @('Debug', 'Release')) {
    $matches = @($configurations | Where-Object {
        $_.SelectSingleNode('./storageModule[@moduleId="org.eclipse.cdt.core.settings"]/@name').Value -eq
            $configurationName
    })
    if ($matches.Count -ne 1) { throw "Expected exactly one $configurationName C configuration." }
    $libm = @($matches[0].SelectNodes(
        './/option[@superClass="xilinx.gnu.c.link.option.libs"]/listOptionValue[@value="m"]'
    ))
    if ($libm.Count -ne 1) {
        throw "$configurationName C linker configuration must contain exactly one libm entry."
    }
}

$buildWrapper = Get-Content -LiteralPath (Join-Path $root 'PROJECT\tests\Build-Axu4evAd9364App.ps1') -Raw
foreach ($fragment in @(
    '$deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds)',
    'Start-Process -FilePath $env:ComSpec',
    '-WindowStyle Hidden',
    'CreateToolhelp32Snapshot',
    'GetProcessTimes',
    '$ownedProcessIds.Contains($parentId)',
    '$ownedProcessBirth[$processId] = Get-RecordCreationUtc',
    'Stop-OwnedBuildProcesses',
    'VERIFY_OWNED_STOPPED',
    'ConvertTo-TclListElement',
    '$buildRoot.Length -gt 80',
    'platform create -xpfm',
    'platform generate',
    'app create -name ad9364app -platform fmcomms2_axu4ev_hw',
    'importsources -name ad9364app',
    'source P:/PROJECT/tests/Build-Axu4evAd9364App.tcl',
    'aarch64-none-elf-nm.exe',
    '--defined-only',
    '$requiredSymbols',
    'Copy-Item -LiteralPath $temporaryElf -Destination $elf -Force'
)) {
    if (-not $buildWrapper.Contains($fragment)) { throw "Missing build wrapper invariant: $fragment" }
}

$wrapperScript = Join-Path $root 'PROJECT\tests\Build-Axu4evAd9364App.ps1'
$wrapperTempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$wrapperTestRoot = [IO.Path]::GetFullPath((Join-Path $wrapperTempBase (
    "w [x]`$;" + [guid]::NewGuid().ToString('N').Substring(0, 8)
)))
if ([IO.Path]::GetDirectoryName($wrapperTestRoot) -ne $wrapperTempBase) {
    throw "Unsafe wrapper-test root: $wrapperTestRoot"
}
$fakeSuccess = Join-Path $wrapperTestRoot 'fake-success.cmd'
$fakeStale = Join-Path $wrapperTestRoot 'fake-stale.cmd'
$fakeDebug = Join-Path $wrapperTestRoot 'fake-debug.cmd'
$fakeTimeout = Join-Path $wrapperTestRoot 'fake-timeout.cmd'
$fakeNmSuccess = Join-Path $wrapperTestRoot 'fake-nm-success.cmd'
$fakeNmMissing = Join-Path $wrapperTestRoot 'fake-nm-missing.cmd'

$fakeSuccessText = @'
@echo off
powershell.exe -NoProfile -Command "$p=$env:TASK5_WRAPPER_TEMP_ELF; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); [IO.File]::WriteAllBytes($p,[byte[]](1..32))"
exit /b %errorlevel%
'@
$fakeStaleText = @'
@echo off
powershell.exe -NoProfile -Command "$p=$env:TASK5_WRAPPER_TEMP_ELF; [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); [IO.File]::WriteAllBytes($p,[byte[]](1..32)); (Get-Item -LiteralPath $p).LastWriteTimeUtc=[DateTime]::UtcNow.AddHours(-1)"
exit /b %errorlevel%
'@
$fakeDebugText = @'
@echo off
powershell.exe -NoProfile -Command "$p=$env:TASK5_WRAPPER_TEMP_ELF.Replace('\Release\','\Debug\'); [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)); [IO.File]::WriteAllBytes($p,[byte[]](1..32))"
exit /b %errorlevel%
'@
$fakeTimeoutText = @'
@echo off
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 30"
exit /b %errorlevel%
'@
$fakeNmSuccessText = @'
@echo off
echo 0000000000000100 T wifi_rf_test_run
echo 0000000000000200 T wifi_rf_prepare_rx_only
echo 0000000000000300 T wifi_rf_capture_channel
echo 0000000000000400 T wifi_rf_analyze_block
exit /b 0
'@
$fakeNmMissingText = @'
@echo off
echo 0000000000000100 T wifi_rf_test_run
echo 0000000000000200 T wifi_rf_prepare_rx_only
echo 0000000000000300 T wifi_rf_capture_channel
exit /b 0
'@

$testEnvironmentNames = @(
    'TASK5_WRAPPER_TEST_MODE', 'TASK5_XSCT_PATH', 'TASK5_NM_PATH',
    'TASK5_TIMEOUT_SECONDS', 'TASK5_TEMP_ROOT', 'TASK5_OUTPUT_ELF',
    'TASK5_AUDIT_PATH', 'TASK5_CLEANUP_FAILURES', 'TASK5_TCL_ENCODE_ONLY'
)

function Invoke-FakeWrapperCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$XsctPath,
        [Parameter(Mandatory = $true)][string]$NmPath,
        [int]$TimeoutSeconds = 20,
        [string]$CleanupFailures = ''
    )

    $savedEnvironment = @{}
    foreach ($environmentName in $testEnvironmentNames) {
        $savedEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable(
            $environmentName, 'Process'
        )
    }
    $outputElf = Join-Path $wrapperTestRoot "$Name-output\ad9364app.elf"
    $audit = Join-Path $wrapperTestRoot "$Name-audit.log"
    try {
        $env:TASK5_WRAPPER_TEST_MODE = '1'
        $env:TASK5_XSCT_PATH = $XsctPath
        $env:TASK5_NM_PATH = $NmPath
        $env:TASK5_TIMEOUT_SECONDS = [string]$TimeoutSeconds
        $env:TASK5_TEMP_ROOT = $wrapperTestRoot
        $env:TASK5_OUTPUT_ELF = $outputElf
        $env:TASK5_AUDIT_PATH = $audit
        $env:TASK5_CLEANUP_FAILURES = $CleanupFailures
        Remove-Item Env:TASK5_TCL_ENCODE_ONLY -ErrorAction SilentlyContinue
        $savedErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $caseOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass `
                -File $wrapperScript -WorkspaceRoot $root 2>&1 | ForEach-Object { "$_" })
            $caseExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorPreference
        }
        return [pscustomobject]@{
            Name = $Name
            ExitCode = $caseExitCode
            Output = $caseOutput
            OutputElf = $outputElf
            Audit = if (Test-Path -LiteralPath $audit) {
                @(Get-Content -LiteralPath $audit)
            }
            else { @() }
        }
    }
    finally {
        foreach ($environmentName in $testEnvironmentNames) {
            $savedValue = $savedEnvironment[$environmentName]
            if ($null -eq $savedValue) {
                [Environment]::SetEnvironmentVariable($environmentName, $null, 'Process')
            }
            else {
                [Environment]::SetEnvironmentVariable($environmentName, $savedValue, 'Process')
            }
        }
    }
}

function Assert-AuditOrder {
    param([string[]]$Audit, [string[]]$Markers)
    $previous = -1
    foreach ($marker in $Markers) {
        $index = -1
        for ($auditIndex = 0; $auditIndex -lt $Audit.Count; $auditIndex++) {
            if ($Audit[$auditIndex].StartsWith($marker, [StringComparison]::Ordinal)) {
                $index = $auditIndex
                break
            }
        }
        if ($index -le $previous) { throw "Wrapper audit marker missing/out of order: $marker" }
        $previous = $index
    }
}

$unrelated = $null
try {
    New-Item -ItemType Directory -Path $wrapperTestRoot | Out-Null
    Set-Content -LiteralPath $fakeSuccess -Value $fakeSuccessText -Encoding Ascii
    Set-Content -LiteralPath $fakeStale -Value $fakeStaleText -Encoding Ascii
    Set-Content -LiteralPath $fakeDebug -Value $fakeDebugText -Encoding Ascii
    Set-Content -LiteralPath $fakeTimeout -Value $fakeTimeoutText -Encoding Ascii
    Set-Content -LiteralPath $fakeNmSuccess -Value $fakeNmSuccessText -Encoding Ascii
    Set-Content -LiteralPath $fakeNmMissing -Value $fakeNmMissingText -Encoding Ascii

    $success = Invoke-FakeWrapperCase 'success' $fakeSuccess $fakeNmSuccess
    if ($success.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $success.OutputElf)) {
        throw "Fake nm-success wrapper case failed: $($success.Output -join [Environment]::NewLine)"
    }
    if ($success.Output -notcontains "PASS: AD9364 application generated: $($success.OutputElf)") {
        throw 'Fake nm-success wrapper case did not report PASS.'
    }
    Assert-AuditOrder $success.Audit @(
        'DEADLINE_TICKS:', 'LAUNCHER_TICKS:', 'NM_PASS:',
        'VERIFY_OWNED_STOPPED', 'UNMAP_VERIFIED', 'DELETE_VERIFIED'
    )
    $deadlineLine = @($success.Audit | Where-Object {
        $_.StartsWith('DEADLINE_TICKS:')
    })[0]
    $launcherLine = @($success.Audit | Where-Object {
        $_.StartsWith('LAUNCHER_TICKS:')
    })[0]
    $deadlineTicks = [int64]$deadlineLine.Split(':')[1]
    $launcherTicks = [int64]$launcherLine.Split(':')[1]
    if ($deadlineTicks -le $launcherTicks) {
        throw 'Wrapper deadline was not established before launcher start.'
    }

    foreach ($rejectCase in @(
        @{ Name = 'stale'; Xsct = $fakeStale; Nm = $fakeNmSuccess; Pattern = 'stale isolated Release ELF' },
        @{ Name = 'debug'; Xsct = $fakeDebug; Nm = $fakeNmSuccess; Pattern = 'exact isolated Release ELF' },
        @{ Name = 'missing-symbol'; Xsct = $fakeSuccess; Nm = $fakeNmMissing; Pattern = 'missing required global text symbol' }
    )) {
        $result = Invoke-FakeWrapperCase $rejectCase.Name $rejectCase.Xsct $rejectCase.Nm
        if ($result.ExitCode -eq 0 -or (Test-Path -LiteralPath $result.OutputElf)) {
            throw "Wrapper rejection case unexpectedly produced an artifact: $($rejectCase.Name)"
        }
        if (($result.Output -join "`n") -notmatch [regex]::Escape($rejectCase.Pattern)) {
            throw "Wrapper rejection case missed expected diagnostic: $($rejectCase.Name): $($result.Output -join ' | ')"
        }
    }

    $unrelated = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
        -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30')
    $timeout = Invoke-FakeWrapperCase 'timeout' $fakeTimeout $fakeNmSuccess 2
    $unrelated.Refresh()
    if ($timeout.ExitCode -eq 0 -or $unrelated.HasExited) {
        throw 'Timeout cleanup failed or stopped an unrelated user process.'
    }
    Assert-AuditOrder $timeout.Audit @(
        'CLEANUP_BEGIN:ProcessShutdown', 'VERIFY_OWNED_STOPPED',
        'CLEANUP_BEGIN:SubstUnmap', 'UNMAP_VERIFIED',
        'CLEANUP_BEGIN:TempDelete', 'DELETE_VERIFIED'
    )

    $cleanup = Invoke-FakeWrapperCase 'cleanup' $fakeSuccess $fakeNmSuccess 20 `
        'SubstUnmap,TempDelete'
    $cleanupText = $cleanup.Output -join "`n"
    if ($cleanup.ExitCode -eq 0 -or $cleanupText -match 'PASS: AD9364 application generated') {
        throw 'Injected cleanup failures must suppress wrapper PASS.'
    }
    foreach ($expectedCleanup in @('Cleanup: SubstUnmap:', 'Cleanup: TempDelete:')) {
        if (-not $cleanupText.Contains($expectedCleanup)) {
            throw "Cleanup aggregation omitted: $expectedCleanup"
        }
    }

    $savedEncode = [Environment]::GetEnvironmentVariable('TASK5_TCL_ENCODE_ONLY', 'Process')
    $savedTestMode = [Environment]::GetEnvironmentVariable('TASK5_WRAPPER_TEST_MODE', 'Process')
    try {
        $env:TASK5_WRAPPER_TEST_MODE = '1'
        $env:TASK5_TCL_ENCODE_ONLY = 'C:/tmp/a b[x]$semi;{c}\d'
        $encoded = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $wrapperScript)
        if ($LASTEXITCODE -ne 0 -or $encoded.Count -ne 1 -or
            $encoded[0] -cne 'C:/tmp/a\ b\[x\]\$semi\;\{c\}\\d') {
            throw "Tcl list-element encoding failed: $($encoded -join ', ')"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('TASK5_TCL_ENCODE_ONLY', $savedEncode, 'Process')
        [Environment]::SetEnvironmentVariable('TASK5_WRAPPER_TEST_MODE', $savedTestMode, 'Process')
    }
}
finally {
    if ($unrelated -and -not $unrelated.HasExited) {
        Stop-Process -Id $unrelated.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $unrelated.Id -Timeout 5 -ErrorAction SilentlyContinue
    }
    if ((Test-Path -LiteralPath $wrapperTestRoot) -and
        [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($wrapperTestRoot)) -eq $wrapperTempBase) {
        Remove-Item -LiteralPath $wrapperTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output 'PASS: Wi-Fi RF capture and UART state-machine source/host behavior passed.'
