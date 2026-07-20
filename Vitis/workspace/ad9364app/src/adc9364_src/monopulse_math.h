#ifndef MONOPULSE_MATH_H
#define MONOPULSE_MATH_H

#include <stdint.h>

#define MONOPULSE_AXIS_DENOMINATOR_SMALL (UINT32_C(1) << 0)
#define MONOPULSE_AXIS_POWER_OVERFLOW    (UINT32_C(1) << 1)

struct monopulse_axis_result {
	int64_t numerator;
	uint64_t denominator;
	int32_t error_q31;
	uint32_t flags;
	uint8_t valid;
};

struct monopulse_power_set {
	uint64_t az_plus;
	uint64_t az_minus;
	uint64_t el_plus;
	uint64_t el_minus;
};

struct monopulse_result {
	struct monopulse_power_set powers;
	struct monopulse_axis_result az;
	struct monopulse_axis_result el;
};

int32_t monopulse_compute_axis(uint64_t plus, uint64_t minus,
			       uint64_t threshold,
			       struct monopulse_axis_result *out);
int32_t monopulse_compute_result(const struct monopulse_power_set *powers,
				 uint64_t threshold,
				 struct monopulse_result *out);

#endif
