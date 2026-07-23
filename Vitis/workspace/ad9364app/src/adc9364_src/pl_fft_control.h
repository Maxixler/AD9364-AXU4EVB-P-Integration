#ifndef PL_FFT_CONTROL_H
#define PL_FFT_CONTROL_H

#include <stdint.h>

#define PL_FFT_VERSION 0x00010000u
#define PL_FFT_SPECTRUM_WORDS 2048u

#define PL_FFT_OK 0
#define PL_FFT_ERR_ARGUMENT (-1)
#define PL_FFT_ERR_CONFIG (-2)
#define PL_FFT_ERR_VERSION (-3)
#define PL_FFT_ERR_NOT_READY (-4)
#define PL_FFT_ERR_TIMEOUT (-5)
#define PL_FFT_ERR_HARDWARE (-6)
#define PL_FFT_ERR_BANK (-7)
#define PL_FFT_ERR_TORN (-8)

typedef uint32_t (*pl_fft_read32_fn)(void *context, uintptr_t address);
typedef uint64_t (*pl_fft_read64_fn)(void *context, uintptr_t address);
typedef void (*pl_fft_write32_fn)(void *context, uintptr_t address,
				  uint32_t value);

struct pl_fft_device {
	void *context;
	uintptr_t control_base;
	uintptr_t bank_base[2];
	pl_fft_read32_fn read32;
	pl_fft_read64_fn read64;
	pl_fft_write32_fn write32;
	uint32_t timeout_polls;
	uint32_t max_snapshot_retries;
};

struct pl_fft_result {
	uint32_t frame_id;
	uint32_t sample_count;
	uint32_t first_sample;
	uint32_t frame_crc32;
	uint32_t dropped_count;
	uint64_t peak_power;
	uint16_t reset_epoch;
	uint16_t peak_bin;
	int16_t peak_re;
	int16_t peak_im;
	uint8_t active_bank;
	uint8_t rf_state;
};

int pl_fft_init(struct pl_fft_device *dev);
int pl_fft_capture_once(struct pl_fft_device *dev,
			uint16_t search_start,
			uint16_t search_stop,
			uint16_t dc_guard,
			uint8_t rf_state,
			struct pl_fft_result *result,
			uint64_t spectrum[PL_FFT_SPECTRUM_WORDS]);
int pl_fft_result_crc_matches(const struct pl_fft_result *result,
			      uint32_t expected_crc);

#endif
