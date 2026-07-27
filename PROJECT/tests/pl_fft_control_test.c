#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pl_fft_control.h"

#define CONTROL_BASE 0x1000u
#define BANK0_BASE   0x2000u
#define BANK1_BASE   0x6000u

#define REG_VERSION       0x00u
#define REG_CONTROL       0x04u
#define REG_STATUS        0x08u
#define REG_FRAME_ID      0x18u
#define REG_RESULT_TAG    0x1cu
#define REG_SAMPLE_COUNT  0x20u
#define REG_PEAK_BIN      0x24u
#define REG_PEAK_POWER_LO 0x28u
#define REG_PEAK_POWER_HI 0x2cu
#define REG_PEAK_RE_IM    0x30u
#define REG_FIRST_SAMPLE  0x34u
#define REG_FRAME_CRC32   0x38u
#define REG_DROPPED_COUNT 0x3cu
#define REG_BANK_VALID    0x40u

#define CONTROL_START         (1u << 0)
#define CONTROL_ABORT         (1u << 1)
#define CONTROL_BANK0_RELEASE (1u << 4)
#define CONTROL_BANK1_RELEASE (1u << 5)

#define STATUS_DONE      (1u << 1)
#define STATUS_CDC_READY (1u << 2)
#define STATUS_FFT_ERROR (1u << 6)
#define STATUS_DROPPED_SAMPLES (1u << 8)

struct fake_mmio {
	uint32_t regs[0x44u / 4u];
	uint64_t bank[2][PL_FFT_SPECTRUM_WORDS];
	uint32_t write_address[32];
	uint32_t write_value[32];
	uint32_t write_count;
	uint32_t start_count;
	uint32_t bank_reads;
	uint32_t mutate_after_bank_read;
	uint32_t completion_status;
	uint8_t auto_complete;
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
	struct fake_mmio *fake = context;

	if (address < CONTROL_BASE || address >= CONTROL_BASE + 0x44u)
		return 0u;
	return fake->regs[(address - CONTROL_BASE) / 4u];
}

static uint64_t fake_read64(void *context, uintptr_t address)
{
	struct fake_mmio *fake = context;
	uint32_t bank;
	uint32_t index;

	if (address >= BANK1_BASE) {
		bank = 1u;
		index = (uint32_t)((address - BANK1_BASE) / 8u);
	} else {
		bank = 0u;
		index = (uint32_t)((address - BANK0_BASE) / 8u);
	}
	if (index >= PL_FFT_SPECTRUM_WORDS)
		return 0u;

	fake->bank_reads++;
	if (fake->mutate_after_bank_read != 0u &&
	    fake->bank_reads == fake->mutate_after_bank_read) {
		fake->regs[REG_FRAME_ID / 4u]++;
		fake->regs[REG_RESULT_TAG / 4u] ^= (1u << 16);
	}
	return fake->bank[bank][index];
}

static void fake_write32(void *context, uintptr_t address, uint32_t value)
{
	struct fake_mmio *fake = context;
	uint32_t offset = (uint32_t)(address - CONTROL_BASE);

	if (fake->write_count < 32u) {
		fake->write_address[fake->write_count] = (uint32_t)address;
		fake->write_value[fake->write_count] = value;
		fake->write_count++;
	}

	if (offset == REG_STATUS) {
		fake->regs[REG_STATUS / 4u] &= ~value;
		return;
	}
	if (offset == REG_CONTROL) {
		if ((value & CONTROL_START) != 0u) {
			fake->start_count++;
			if (fake->auto_complete != 0u)
				fake->regs[REG_STATUS / 4u] |=
					STATUS_DONE | fake->completion_status;
		}
		if ((value & CONTROL_ABORT) != 0u)
			fake->regs[REG_STATUS / 4u] &= ~STATUS_DONE;
		if ((value & CONTROL_BANK0_RELEASE) != 0u)
			fake->regs[REG_BANK_VALID / 4u] &= ~1u;
		if ((value & CONTROL_BANK1_RELEASE) != 0u)
			fake->regs[REG_BANK_VALID / 4u] &= ~2u;
		return;
	}
	if (offset < 0x44u)
		fake->regs[offset / 4u] = value;
}

static void fake_init(struct fake_mmio *fake, uint32_t active_bank)
{
	uint32_t index;

	memset(fake, 0, sizeof(*fake));
	fake->regs[REG_VERSION / 4u] = PL_FFT_VERSION;
	fake->regs[REG_STATUS / 4u] = STATUS_CDC_READY;
	fake->regs[REG_FRAME_ID / 4u] = 23u;
	fake->regs[REG_RESULT_TAG / 4u] =
		(7u << 16) | (5u << 1) | (active_bank & 1u);
	fake->regs[REG_SAMPLE_COUNT / 4u] = PL_FFT_SPECTRUM_WORDS;
	fake->regs[REG_PEAK_BIN / 4u] = 137u;
	fake->regs[REG_PEAK_POWER_LO / 4u] = 0x89abcdefu;
	fake->regs[REG_PEAK_POWER_HI / 4u] = 1u;
	fake->regs[REG_PEAK_RE_IM / 4u] =
		((uint32_t)(uint16_t)-2345 << 16) | (uint16_t)-1234;
	fake->regs[REG_FIRST_SAMPLE / 4u] = 0x13572468u;
	fake->regs[REG_FRAME_CRC32 / 4u] = 0xdeadbeefu;
	fake->regs[REG_DROPPED_COUNT / 4u] = 3u;
	fake->regs[REG_BANK_VALID / 4u] = 1u << active_bank;
	fake->auto_complete = 1u;
	for (index = 0u; index < PL_FFT_SPECTRUM_WORDS; index++) {
		fake->bank[0][index] = 0x1000000000000000ull + index;
		fake->bank[1][index] = 0x2000000000000000ull + index;
	}
}

static struct pl_fft_device make_device(struct fake_mmio *fake)
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

static void test_configuration_validation(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 0u);
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 100u, 99u, 0u, 0u,
				  &result, spectrum) == PL_FFT_ERR_CONFIG);
	CHECK(pl_fft_capture_once(&dev, 0u, 2048u, 0u, 0u,
				  &result, spectrum) == PL_FFT_ERR_CONFIG);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 1025u, 0u,
				  &result, spectrum) == PL_FFT_ERR_CONFIG);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 8u,
				  &result, spectrum) == PL_FFT_ERR_CONFIG);
	CHECK(fake.start_count == 0u);
}

static void test_single_shot_bank1_and_metadata(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];
	uint32_t index;

	fake_init(&fake, 1u);
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 12u, 1900u, 4u, 5u,
				  &result, spectrum) == PL_FFT_OK);
	CHECK(fake.start_count == 1u);
	CHECK(result.frame_id == 23u);
	CHECK(result.active_bank == 1u);
	CHECK(result.rf_state == 5u);
	CHECK(result.reset_epoch == 7u);
	CHECK(result.sample_count == PL_FFT_SPECTRUM_WORDS);
	CHECK(result.peak_bin == 137u);
	CHECK(result.peak_power == 0x189abcdefull);
	CHECK(result.peak_re == -1234);
	CHECK(result.peak_im == -2345);
	CHECK(result.first_sample == 0x13572468u);
	CHECK(result.frame_crc32 == 0xdeadbeefu);
	CHECK(result.dropped_count == 3u);
	CHECK(pl_fft_result_crc_matches(&result, 0xdeadbeefu));
	CHECK(!pl_fft_result_crc_matches(&result, 0xdeadbeeeu));
	for (index = 0u; index < PL_FFT_SPECTRUM_WORDS; index++)
		CHECK(spectrum[index] == 0x2000000000000000ull + index);
	CHECK(fake.regs[REG_BANK_VALID / 4u] == 0u);
	CHECK(fake.write_value[fake.write_count - 1u] ==
	      CONTROL_BANK1_RELEASE);
}

static void test_torn_snapshot_is_retried(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 0u);
	fake.mutate_after_bank_read = 17u;
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 5u,
				  &result, spectrum) == PL_FFT_OK);
	CHECK(fake.bank_reads == 2u * PL_FFT_SPECTRUM_WORDS);
	CHECK(result.frame_id == 24u);
	CHECK(result.reset_epoch == 6u);
	CHECK(spectrum[0] == 0x1000000000000000ull);
}

static void test_timeout_aborts(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 0u);
	fake.auto_complete = 0u;
	dev = make_device(&fake);
	dev.timeout_polls = 3u;
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 0u,
				  &result, spectrum) == PL_FFT_ERR_TIMEOUT);
	CHECK(fake.start_count == 1u);
	CHECK(fake.write_value[fake.write_count - 1u] == CONTROL_ABORT);
}

static void test_hardware_error_is_cleared_w1c(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 0u);
	fake.auto_complete = 0u;
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	fake.regs[REG_STATUS / 4u] |= STATUS_FFT_ERROR;
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 0u,
				  &result, spectrum) == PL_FFT_ERR_HARDWARE);
	CHECK((fake.regs[REG_STATUS / 4u] & STATUS_FFT_ERROR) == 0u);
	CHECK(fake.write_address[fake.write_count - 1u] ==
	      CONTROL_BASE + REG_STATUS);
	CHECK(fake.write_value[fake.write_count - 1u] == STATUS_FFT_ERROR);
}

static void test_single_shot_dropped_samples_is_nonfatal(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 0u);
	fake.completion_status = STATUS_DROPPED_SAMPLES;
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 0u,
				  &result, spectrum) == PL_FFT_OK);
	CHECK((fake.regs[REG_STATUS / 4u] & STATUS_DROPPED_SAMPLES) == 0u);
}

static void test_preexisting_hardware_error_is_reported_by_init(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;

	fake_init(&fake, 0u);
	fake.regs[REG_STATUS / 4u] |= STATUS_FFT_ERROR;
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_ERR_HARDWARE);
	CHECK((fake.regs[REG_STATUS / 4u] & STATUS_FFT_ERROR) == 0u);
	CHECK(fake.write_address[fake.write_count - 1u] ==
	      CONTROL_BASE + REG_STATUS);
	CHECK(fake.write_value[fake.write_count - 1u] == STATUS_FFT_ERROR);
}

static void test_missing_valid_bank_is_rejected(void)
{
	struct fake_mmio fake;
	struct pl_fft_device dev;
	struct pl_fft_result result;
	uint64_t spectrum[PL_FFT_SPECTRUM_WORDS];

	fake_init(&fake, 1u);
	fake.regs[REG_BANK_VALID / 4u] = 1u;
	dev = make_device(&fake);
	CHECK(pl_fft_init(&dev) == PL_FFT_OK);
	CHECK(pl_fft_capture_once(&dev, 0u, 2047u, 0u, 5u,
				  &result, spectrum) == PL_FFT_ERR_BANK);
	CHECK(fake.regs[REG_BANK_VALID / 4u] == 1u);
}

int main(void)
{
	test_configuration_validation();
	test_single_shot_bank1_and_metadata();
	test_torn_snapshot_is_retried();
	test_timeout_aborts();
	test_hardware_error_is_cleared_w1c();
	test_single_shot_dropped_samples_is_nonfatal();
	test_preexisting_hardware_error_is_reported_by_init();
	test_missing_valid_bank_is_rejected();

	if (failures != 0) {
		printf("FAIL: pl_fft_control failures=%d\n", failures);
		return 1;
	}
	printf("PASS: pl_fft_control single-shot driver\n");
	return 0;
}
