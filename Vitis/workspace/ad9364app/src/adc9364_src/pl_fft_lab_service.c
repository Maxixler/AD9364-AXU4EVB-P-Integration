#include "pl_fft_lab_service.h"

#include <stddef.h>
#include <string.h>

#define PL_FFT_LAB_BOARD_AXU4EVB_P 1u
#define PL_FFT_LAB_RF_AD9364 1u
#define PL_FFT_LAB_FEATURES 0x00000007u
#define PL_FFT_LAB_RELEASE_ID "monopulse-live-lab-v1"

static int32_t service_get_info(
	struct pl_fft_lab_service *service,
	const struct pl_fft_lab_command *command)
{
	struct pl_fft_lab_rf_snapshot rf;
	struct pl_fft_lab_info info;
	int32_t status;

	status = service->read_rf(service->rf_context, &rf);
	if (status != PL_FFT_OK)
		return pl_fft_lab_write_error(
			&service->writer, command->sequence,
			PL_FFT_ERR_HARDWARE, PL_FFT_LAB_STAGE_CONFIG);

	memset(&info, 0, sizeof(info));
	info.board_code = PL_FFT_LAB_BOARD_AXU4EVB_P;
	info.rf_device_code = PL_FFT_LAB_RF_AD9364;
	info.firmware_version = PL_FFT_VERSION;
	info.feature_bits = PL_FFT_LAB_FEATURES;
	info.fft_size = PL_FFT_SPECTRUM_WORDS;
	info.spectrum_word_bytes = sizeof(uint64_t);
	info.rf_state_count = 1u;
	info.sample_rate_hz = rf.sample_rate_hz;
	info.rx_bandwidth_hz = rf.rx_bandwidth_hz;
	info.lo_hz = rf.lo_hz;
	memcpy(info.release_id, PL_FFT_LAB_RELEASE_ID,
	       sizeof(PL_FFT_LAB_RELEASE_ID) - 1u);
	return pl_fft_lab_write_info(
		&service->writer, command->sequence, &info);
}

static int32_t write_capture_error(
	struct pl_fft_lab_service *service, uint32_t sequence,
	int32_t error)
{
	uint16_t stage = PL_FFT_LAB_STAGE_CAPTURE;

	if (error == PL_FFT_ERR_CONFIG ||
	    error == PL_FFT_ERR_ARGUMENT)
		stage = PL_FFT_LAB_STAGE_CONFIG;
	else if (error == PL_FFT_ERR_NOT_READY)
		stage = PL_FFT_LAB_STAGE_BUSY;
	return pl_fft_lab_write_error(
		&service->writer, sequence, error, stage);
}

static int capture_config_valid(const struct pl_fft_lab_command *command)
{
	return command->payload_length == 8u &&
	       command->capture.search_start <=
		       command->capture.search_stop &&
	       command->capture.search_stop <
		       PL_FFT_SPECTRUM_WORDS &&
	       command->capture.dc_guard <= 1024u &&
	       command->capture.rf_state <= 7u;
}

static int32_t service_capture_once(
	struct pl_fft_lab_service *service,
	const struct pl_fft_lab_command *command)
{
	struct pl_fft_lab_rf_snapshot rf;
	struct pl_fft_lab_spectrum response;
	struct pl_fft_result result;
	int32_t status;

	if (!capture_config_valid(command))
		return write_capture_error(
			service, command->sequence, PL_FFT_ERR_CONFIG);
	status = service->read_rf(service->rf_context, &rf);
	if (status != PL_FFT_OK)
		return write_capture_error(
			service, command->sequence, PL_FFT_ERR_HARDWARE);

	memset(&result, 0, sizeof(result));
	status = pl_fft_capture_once(
		service->fft,
		command->capture.search_start,
		command->capture.search_stop,
		command->capture.dc_guard,
		command->capture.rf_state,
		&result, service->spectrum);
	if (status != PL_FFT_OK)
		return write_capture_error(
			service, command->sequence, status);
	if (result.hardware_flags != 0u ||
	    result.sample_count != PL_FFT_SPECTRUM_WORDS)
		return write_capture_error(
			service, command->sequence, PL_FFT_ERR_HARDWARE);

	memset(&response, 0, sizeof(response));
	response.frame_id = result.frame_id;
	response.sample_count = (uint16_t)result.sample_count;
	response.fft_size = PL_FFT_SPECTRUM_WORDS;
	response.sample_rate_hz = rf.sample_rate_hz;
	response.rx_bandwidth_hz = rf.rx_bandwidth_hz;
	response.lo_hz = rf.lo_hz;
	response.frame_crc32 = result.frame_crc32;
	response.skipped_sample_count = result.dropped_count;
	response.peak_power = result.peak_power;
	response.peak_bin = result.peak_bin;
	response.peak_re = result.peak_re;
	response.peak_im = result.peak_im;
	response.reset_epoch = result.reset_epoch;
	response.rf_state = result.rf_state;
	response.active_bank = result.active_bank;
	response.hardware_flags = result.hardware_flags;
	return pl_fft_lab_write_spectrum(
		&service->writer, command->sequence,
		&response, service->spectrum);
}

int32_t pl_fft_lab_service_command(
	struct pl_fft_lab_service *service,
	const struct pl_fft_lab_command *command)
{
	if (service == NULL || command == NULL ||
	    service->fft == NULL || service->writer.write == NULL ||
	    service->read_rf == NULL || service->spectrum == NULL)
		return PL_FFT_LAB_ERR_ARGUMENT;
	if (command->type == PL_FFT_LAB_GET_INFO &&
	    command->payload_length == 0u)
		return service_get_info(service, command);
	if (command->type == PL_FFT_LAB_CAPTURE_ONCE)
		return service_capture_once(service, command);
	return pl_fft_lab_write_error(
		&service->writer, command->sequence,
		PL_FFT_ERR_CONFIG, PL_FFT_LAB_STAGE_CONFIG);
}
