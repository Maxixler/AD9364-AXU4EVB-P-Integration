#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pl_fft_control.h"
#include "pl_fft_monitor.h"

#define CONTROL_BASE 0x1000u
#define BANK0_BASE 0x2000u
#define BANK1_BASE 0x6000u

#define REG_VERSION 0x00u
#define REG_CONTROL 0x04u
#define REG_STATUS 0x08u
#define REG_FRAME_ID 0x18u
#define REG_RESULT_TAG 0x1cu
#define REG_SAMPLE_COUNT 0x20u
#define REG_BANK_VALID 0x40u

#define CONTROL_START (1u << 0)
#define CONTROL_BANK0_RELEASE (1u << 4)
#define CONTROL_BANK1_RELEASE (1u << 5)
#define STATUS_DONE (1u << 1)
#define STATUS_CDC_READY (1u << 2)
#define STATUS_FFT_ERROR (1u << 6)

struct fake_monitor {
	uint32_t regs[0x44u / 4u];
	uint64_t bank[2][PL_FFT_SPECTRUM_WORDS];
	uint32_t start_count;
	uint32_t fail_start;
	uint32_t delay_count;
	uint32_t report_count;
	uint32_t last_delay_ms;
	uint32_t last_sequence;
	uint32_t last_total;
};

static int failures;

#define CHECK(condition) do { \
	if (!(condition)) { \
		printf("FAIL line=%d condition=%s\n", __LINE__, #condition); \
		failures++; \
		return; \
	} \
} while (0)

static uint32_t fake_read32(void *context, uintptr_t address)
{
	struct fake_monitor *fake = context;

	if (address < CONTROL_BASE || address >= CONTROL_BASE + 0x44u)
		return 0u;
	return fake->regs[(address - CONTROL_BASE) / 4u];
}

static uint64_t fake_read64(void *context, uintptr_t address)
{
	struct fake_monitor *fake = context;
	uint32_t bank = address >= BANK1_BASE ? 1u : 0u;
	uintptr_t base = bank == 0u ? BANK0_BASE : BANK1_BASE;
	uint32_t index = (uint32_t)((address - base) / sizeof(uint64_t));

	return index < PL_FFT_SPECTRUM_WORDS ? fake->bank[bank][index] : 0u;
}

static void fake_write32(void *context, uintptr_t address, uint32_t value)
{
	struct fake_monitor *fake = context;
	uint32_t offset = (uint32_t)(address - CONTROL_BASE);

	if (offset == REG_STATUS) {
		fake->regs[REG_STATUS / 4u] &= ~value;
		return;
	}
	if (offset == REG_CONTROL) {
		if ((value & CONTROL_START) != 0u) {
			uint32_t bank;

			fake->start_count++;
			bank = fake->start_count & 1u;
			fake->regs[REG_FRAME_ID / 4u] = fake->start_count;
			fake->regs[REG_RESULT_TAG / 4u] = bank;
			fake->regs[REG_BANK_VALID / 4u] = 1u << bank;
			fake->regs[REG_STATUS / 4u] |= STATUS_DONE;
			if (fake->start_count == fake->fail_start)
				fake->regs[REG_STATUS / 4u] |= STATUS_FFT_ERROR;
		}
		if ((value & CONTROL_BANK0_RELEASE) != 0u)
			fake->regs[REG_BANK_VALID / 4u] &= ~1u;
		if ((value & CONTROL_BANK1_RELEASE) != 0u)
			fake->regs[REG_BANK_VALID / 4u] &= ~2u;
		return;
	}
	if (offset < 0x44u)
		fake->regs[offset / 4u] = value;
}

static void fake_delay(void *context, uint32_t delay_ms)
{
	struct fake_monitor *fake = context;

	fake->delay_count++;
	fake->last_delay_ms = delay_ms;
}

static void fake_report(void *context, uint32_t sequence, uint32_t total,
			const struct pl_fft_result *result)
{
	struct fake_monitor *fake = context;

	CHECK(result != NULL);
	fake->report_count++;
	fake->last_sequence = sequence;
	fake->last_total = total;
}

static void fake_init(struct fake_monitor *fake)
{
	uint32_t index;

	memset(fake, 0, sizeof(*fake));
	fake->regs[REG_VERSION / 4u] = PL_FFT_VERSION;
	fake->regs[REG_STATUS / 4u] = STATUS_CDC_READY;
	fake->regs[REG_SAMPLE_COUNT / 4u] = PL_FFT_SPECTRUM_WORDS;
	for (index = 0u; index < PL_FFT_SPECTRUM_WORDS; index++) {
		fake->bank[0][index] = 0x1000000000000000ull + index;
		fake->bank[1][index] = 0x2000000000000000ull + index;
	}
}

static struct pl_fft_device make_device(struct fake_monitor *fake)
{
	struct pl_fft_device dev;

	memset(&dev, 0, sizeof(dev));
	dev.context = fake;
	dev.control_base = CONTROL_BASE;
	dev.bank_base[0] = BANK0_BASE;
	dev.bank_base[1] = BANK1_BASE;
	dev.read32 = fake_read32;
	dev.read64 = fake_read64;
	dev.write32 = fake_write32;
	dev.timeout_polls = 8u;
	dev.max_snapshot_retries = 2u;
	return dev;
}

static struct pl_fft_monitor make_monitor(struct fake_monitor *fake,
					  struct pl_fft_device *dev)
{
	struct pl_fft_monitor monitor;

	monitor.device = dev;
	monitor.callback_context = fake;
	monitor.delay_ms = fake_delay;
	monitor.report_frame = fake_report;
	return monitor;
}

static void test_100_frames_and_99_delays(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 0;

	fake_init(&fake);
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_monitor_run(&monitor, 100u, 1000u,
				 spectrum, &completed) == PL_FFT_OK);
	CHECK(completed == 100u);
	CHECK(fake.start_count == 100u);
	CHECK(fake.report_count == 100u);
	CHECK(fake.delay_count == 99u);
	CHECK(fake.last_delay_ms == 1000u);
	CHECK(fake.last_sequence == 100u);
	CHECK(fake.last_total == 100u);
}

static void test_first_capture_error_is_fail_fast(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 99u;

	fake_init(&fake);
	fake.fail_start = 17u;
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_monitor_run(&monitor, 100u, 1000u,
				 spectrum, &completed) == PL_FFT_ERR_HARDWARE);
	CHECK(completed == 16u);
	CHECK(fake.start_count == 17u);
	CHECK(fake.report_count == 16u);
	CHECK(fake.delay_count == 16u);
}

static void test_invalid_arguments_do_not_touch_hardware(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 77u;

	fake_init(&fake);
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_monitor_run(NULL, 1u, 1u, spectrum, &completed) ==
	      PL_FFT_ERR_ARGUMENT);
	monitor.device = NULL;
	CHECK(pl_fft_monitor_run(&monitor, 1u, 1u, spectrum, &completed) ==
	      PL_FFT_ERR_ARGUMENT);
	monitor.device = &dev;
	monitor.delay_ms = NULL;
	CHECK(pl_fft_monitor_run(&monitor, 1u, 1u, spectrum, &completed) ==
	      PL_FFT_ERR_ARGUMENT);
	monitor.delay_ms = fake_delay;
	monitor.report_frame = NULL;
	CHECK(pl_fft_monitor_run(&monitor, 1u, 1u, spectrum, &completed) ==
	      PL_FFT_ERR_ARGUMENT);
	monitor.report_frame = fake_report;
	CHECK(pl_fft_monitor_run(&monitor, 1u, 1u, NULL, &completed) ==
	      PL_FFT_ERR_ARGUMENT);
	CHECK(pl_fft_monitor_run(&monitor, 1u, 1u, spectrum, NULL) ==
	      PL_FFT_ERR_ARGUMENT);
	CHECK(fake.start_count == 0u);
	CHECK(fake.report_count == 0u);
	CHECK(fake.delay_count == 0u);
	CHECK(completed == 77u);
}

static void test_invalid_configuration_does_not_touch_hardware(void)
{
	struct fake_monitor fake;
	struct pl_fft_device dev;
	struct pl_fft_monitor monitor;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t completed = 77u;

	fake_init(&fake);
	dev = make_device(&fake);
	monitor = make_monitor(&fake, &dev);
	CHECK(pl_fft_monitor_run(&monitor, 0u, 1000u, spectrum, &completed) ==
	      PL_FFT_ERR_CONFIG);
	CHECK(pl_fft_monitor_run(&monitor, 1u, 0u, spectrum, &completed) ==
	      PL_FFT_ERR_CONFIG);
	CHECK(fake.start_count == 0u);
	CHECK(fake.report_count == 0u);
	CHECK(fake.delay_count == 0u);
	CHECK(completed == 77u);
}

int main(void)
{
	test_100_frames_and_99_delays();
	test_first_capture_error_is_fail_fast();
	test_invalid_arguments_do_not_touch_hardware();
	test_invalid_configuration_does_not_touch_hardware();
	if (failures != 0) {
		printf("FAIL: pl_fft_monitor failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_monitor policy\n");
	return 0;
}
