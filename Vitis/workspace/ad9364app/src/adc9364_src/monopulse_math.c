#include "monopulse_math.h"

#include <errno.h>
#include <limits.h>
#include <stddef.h>

static uint64_t monopulse_saturating_sum(uint64_t plus, uint64_t minus,
					 uint32_t *flags)
{
	if (plus > (UINT64_MAX - minus)) {
		*flags |= MONOPULSE_AXIS_POWER_OVERFLOW;
		return UINT64_MAX;
	}

	return plus + minus;
}

static int64_t monopulse_saturating_difference(uint64_t plus, uint64_t minus,
						uint32_t *flags)
{
	const uint64_t int64_max = (uint64_t)INT64_MAX;
	const uint64_t int64_min_magnitude = int64_max + UINT64_C(1);
	uint64_t magnitude;

	if (plus >= minus) {
		magnitude = plus - minus;
		if (magnitude > int64_max) {
			*flags |= MONOPULSE_AXIS_POWER_OVERFLOW;
			return INT64_MAX;
		}
		return (int64_t)magnitude;
	}

	magnitude = minus - plus;
	if (magnitude > int64_min_magnitude) {
		*flags |= MONOPULSE_AXIS_POWER_OVERFLOW;
		return INT64_MIN;
	}
	if (magnitude == int64_min_magnitude) {
		return INT64_MIN;
	}
	return -(int64_t)magnitude;
}

static int32_t monopulse_q31_error(uint64_t plus, uint64_t minus)
{
	uint64_t denominator_low;
	uint64_t remainder_low;
	uint64_t magnitude;
	uint32_t q31_magnitude = 0U;
	uint8_t denominator_high;
	uint8_t remainder_high = 0U;
	uint8_t negative;
	uint32_t bit;

	if (plus >= minus) {
		magnitude = plus - minus;
		negative = 0U;
	} else {
		magnitude = minus - plus;
		negative = 1U;
	}

	denominator_low = plus + minus;
	denominator_high = (plus > (UINT64_MAX - minus)) ? 1U : 0U;
	if (((denominator_high == 0U) && (denominator_low == 0U)) ||
	    (magnitude == 0U)) {
		return 0;
	}
	if ((denominator_high == 0U) && (magnitude == denominator_low)) {
		return (negative != 0U) ? INT32_MIN : INT32_MAX;
	}

	/*
	 * The true denominator is up to 65 bits.  Shift-and-subtract division
	 * retains that extra bit in remainder_high, so no overflowing product is
	 * required to form magnitude * 2^31.
	 */
	remainder_low = magnitude;
	for (bit = 0U; bit < 31U; ++bit) {
		uint64_t shifted_low = remainder_low << 1;
		uint8_t shifted_high = (uint8_t)((remainder_high << 1) |
						(remainder_low >> 63));
		uint8_t quotient_bit = 0U;

		if ((shifted_high > denominator_high) ||
		    ((shifted_high == denominator_high) &&
		     (shifted_low >= denominator_low))) {
			uint8_t borrow = (shifted_low < denominator_low) ? 1U : 0U;

			shifted_low -= denominator_low;
			shifted_high = (uint8_t)(shifted_high - denominator_high -
							borrow);
			quotient_bit = 1U;
		}

		remainder_low = shifted_low;
		remainder_high = shifted_high;
		q31_magnitude = (q31_magnitude << 1) | quotient_bit;
	}
	if (q31_magnitude > (uint32_t)INT32_MAX) {
		return (negative != 0U) ? INT32_MIN : INT32_MAX;
	}
	if (negative != 0U) {
		return -(int32_t)q31_magnitude;
	}
	return (int32_t)q31_magnitude;
}

int32_t monopulse_compute_axis(uint64_t plus, uint64_t minus,
			       uint64_t threshold,
			       struct monopulse_axis_result *out)
{
	if ((out == NULL) || (threshold == 0U)) {
		return -EINVAL;
	}

	out->flags = 0U;
	out->denominator = monopulse_saturating_sum(plus, minus, &out->flags);
	out->numerator = monopulse_saturating_difference(plus, minus,
							  &out->flags);
	out->error_q31 = monopulse_q31_error(plus, minus);
	out->valid = (out->denominator >= threshold) ? 1U : 0U;
	if (out->valid == 0U) {
		out->flags |= MONOPULSE_AXIS_DENOMINATOR_SMALL;
	}

	return 0;
}

int32_t monopulse_compute_result(const struct monopulse_power_set *powers,
				 uint64_t threshold,
				 struct monopulse_result *out)
{
	int32_t status;

	if ((powers == NULL) || (out == NULL) || (threshold == 0U)) {
		return -EINVAL;
	}

	out->powers = *powers;
	status = monopulse_compute_axis(powers->az_plus, powers->az_minus,
					threshold, &out->az);
	if (status != 0) {
		return status;
	}
	return monopulse_compute_axis(powers->el_plus, powers->el_minus,
				      threshold, &out->el);
}
