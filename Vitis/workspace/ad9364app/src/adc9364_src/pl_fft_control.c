#include "pl_fft_control.h"

#include <stddef.h>

#define REG_VERSION          0x00u
#define REG_CONTROL          0x04u
#define REG_STATUS           0x08u
#define REG_SEARCH_RANGE     0x0cu
#define REG_DC_GUARD_WINDOW  0x10u
#define REG_COMMAND_TAG      0x14u
#define REG_FRAME_ID         0x18u
#define REG_RESULT_TAG       0x1cu
#define REG_SAMPLE_COUNT     0x20u
#define REG_PEAK_BIN         0x24u
#define REG_PEAK_POWER_LO    0x28u
#define REG_PEAK_POWER_HI    0x2cu
#define REG_PEAK_RE_IM       0x30u
#define REG_FIRST_SAMPLE     0x34u
#define REG_FRAME_CRC32      0x38u
#define REG_DROPPED_COUNT    0x3cu
#define REG_BANK_VALID       0x40u

#define CONTROL_START         (1u << 0)
#define CONTROL_ABORT         (1u << 1)
#define CONTROL_BANK0_RELEASE (1u << 4)
#define CONTROL_BANK1_RELEASE (1u << 5)

#define STATUS_BUSY            (1u << 0)
#define STATUS_DONE            (1u << 1)
#define STATUS_CDC_READY       (1u << 2)
#define STATUS_ERROR_MASK      (0x7f8u)

static uint32_t reg_read(const struct pl_fft_device *dev, uint32_t offset)
{
	return dev->read32(dev->context, dev->control_base + offset);
}

static void reg_write(const struct pl_fft_device *dev, uint32_t offset,
		      uint32_t value)
{
	dev->write32(dev->context, dev->control_base + offset, value);
}

static int device_valid(const struct pl_fft_device *dev)
{
	return dev != NULL && dev->read32 != NULL && dev->read64 != NULL &&
	       dev->write32 != NULL && dev->control_base != 0u &&
	       dev->bank_base[0] != 0u && dev->bank_base[1] != 0u &&
	       dev->timeout_polls != 0u && dev->max_snapshot_retries != 0u;
}

static void read_result_fields(const struct pl_fft_device *dev,
			       uint32_t frame_id,
			       uint32_t result_tag,
			       struct pl_fft_result *result)
{
	uint32_t peak_re_im = reg_read(dev, REG_PEAK_RE_IM);
	uint64_t peak_power = reg_read(dev, REG_PEAK_POWER_LO);

	peak_power |= ((uint64_t)(reg_read(dev, REG_PEAK_POWER_HI) & 1u)
		       << 32);
	result->frame_id = frame_id;
	result->active_bank = (uint8_t)(result_tag & 1u);
	result->rf_state = (uint8_t)((result_tag >> 1) & 7u);
	result->reset_epoch = (uint16_t)(result_tag >> 16);
	result->sample_count = reg_read(dev, REG_SAMPLE_COUNT);
	result->peak_bin = (uint16_t)(reg_read(dev, REG_PEAK_BIN) & 0x7ffu);
	result->peak_power = peak_power;
	result->peak_re = (int16_t)(peak_re_im & 0xffffu);
	result->peak_im = (int16_t)(peak_re_im >> 16);
	result->first_sample = reg_read(dev, REG_FIRST_SAMPLE);
	result->frame_crc32 = reg_read(dev, REG_FRAME_CRC32);
	result->dropped_count = reg_read(dev, REG_DROPPED_COUNT);
}

int pl_fft_init(struct pl_fft_device *dev)
{
	uint32_t status;

	if (!device_valid(dev))
		return PL_FFT_ERR_ARGUMENT;
	if (reg_read(dev, REG_VERSION) != PL_FFT_VERSION)
		return PL_FFT_ERR_VERSION;

	status = reg_read(dev, REG_STATUS);
	if ((status & STATUS_CDC_READY) == 0u)
		return PL_FFT_ERR_NOT_READY;
	if ((status & STATUS_BUSY) != 0u)
		return PL_FFT_ERR_NOT_READY;
	if ((status & STATUS_ERROR_MASK) != 0u) {
		reg_write(dev, REG_STATUS, status & STATUS_ERROR_MASK);
		return PL_FFT_ERR_HARDWARE;
	}

	reg_write(dev, REG_STATUS, status & STATUS_DONE);
	return PL_FFT_OK;
}

int pl_fft_capture_once(struct pl_fft_device *dev,
			uint16_t search_start,
			uint16_t search_stop,
			uint16_t dc_guard,
			uint8_t rf_state,
			struct pl_fft_result *result,
			uint64_t spectrum[PL_FFT_SPECTRUM_WORDS])
{
	uint32_t status;
	uint32_t poll;
	uint32_t attempt;

	if (!device_valid(dev) || result == NULL || spectrum == NULL)
		return PL_FFT_ERR_ARGUMENT;
	if (search_start > search_stop || search_stop >= PL_FFT_SPECTRUM_WORDS ||
	    dc_guard > 1024u || rf_state > 7u)
		return PL_FFT_ERR_CONFIG;

	status = reg_read(dev, REG_STATUS);
	if ((status & STATUS_CDC_READY) == 0u || (status & STATUS_BUSY) != 0u)
		return PL_FFT_ERR_NOT_READY;
	if ((status & STATUS_ERROR_MASK) != 0u) {
		reg_write(dev, REG_STATUS, status & STATUS_ERROR_MASK);
		return PL_FFT_ERR_HARDWARE;
	}
	reg_write(dev, REG_STATUS, status & STATUS_DONE);
	reg_write(dev, REG_SEARCH_RANGE,
		  ((uint32_t)search_stop << 16) | search_start);
	reg_write(dev, REG_DC_GUARD_WINDOW, dc_guard);
	reg_write(dev, REG_COMMAND_TAG, rf_state);
	reg_write(dev, REG_CONTROL, CONTROL_START);

	for (poll = 0u; poll < dev->timeout_polls; poll++) {
		status = reg_read(dev, REG_STATUS);
		if ((status & STATUS_ERROR_MASK) != 0u) {
			reg_write(dev, REG_STATUS, status & STATUS_ERROR_MASK);
			return PL_FFT_ERR_HARDWARE;
		}
		if ((status & STATUS_DONE) != 0u)
			break;
	}
	if (poll == dev->timeout_polls) {
		reg_write(dev, REG_CONTROL, CONTROL_ABORT);
		return PL_FFT_ERR_TIMEOUT;
	}

	for (attempt = 0u; attempt < dev->max_snapshot_retries; attempt++) {
		struct pl_fft_result snapshot;
		uint32_t frame_before = reg_read(dev, REG_FRAME_ID);
		uint32_t tag_before = reg_read(dev, REG_RESULT_TAG);
		uint32_t active_bank = tag_before & 1u;
		uint32_t bank_valid = reg_read(dev, REG_BANK_VALID);
		uint32_t index;
		uint32_t frame_after;
		uint32_t tag_after;

		if ((bank_valid & (1u << active_bank)) == 0u)
			return PL_FFT_ERR_BANK;

		read_result_fields(dev, frame_before, tag_before, &snapshot);
		for (index = 0u; index < PL_FFT_SPECTRUM_WORDS; index++) {
			spectrum[index] = dev->read64(
				dev->context,
				dev->bank_base[active_bank] +
				(uintptr_t)index * sizeof(uint64_t));
		}
		frame_after = reg_read(dev, REG_FRAME_ID);
		tag_after = reg_read(dev, REG_RESULT_TAG);
		if (frame_before != frame_after || tag_before != tag_after)
			continue;
		if ((reg_read(dev, REG_BANK_VALID) & (1u << active_bank)) == 0u)
			continue;

		*result = snapshot;
		reg_write(dev, REG_STATUS, STATUS_DONE);
		reg_write(dev, REG_CONTROL,
			  active_bank == 0u ? CONTROL_BANK0_RELEASE :
					     CONTROL_BANK1_RELEASE);
		return PL_FFT_OK;
	}

	return PL_FFT_ERR_TORN;
}

int pl_fft_result_crc_matches(const struct pl_fft_result *result,
			      uint32_t expected_crc)
{
	return result != NULL && result->frame_crc32 == expected_crc;
}
