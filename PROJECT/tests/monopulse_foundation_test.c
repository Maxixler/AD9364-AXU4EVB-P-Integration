#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

#include "monopulse_math.h"
#include "monopulse_sequence.h"

static void test_axis_vectors(void)
{
	struct monopulse_axis_result r;

	assert(monopulse_compute_axis(300, 100, 1, &r) == 0);
	assert(r.numerator == 200);
	assert(r.denominator == 400);
	assert(r.error_q31 == INT32_C(1073741824));
	assert(r.valid == 1U);

	assert(monopulse_compute_axis(100, 300, 1, &r) == 0);
	assert(r.numerator == -200);
	assert(r.error_q31 == -INT32_C(1073741824));

	assert(monopulse_compute_axis(200, 200, 1, &r) == 0);
	assert(r.error_q31 == 0);

	assert(monopulse_compute_axis(1, 0, 1, &r) == 0);
	assert(r.error_q31 == INT32_MAX);
	assert(monopulse_compute_axis(0, 1, 1, &r) == 0);
	assert(r.error_q31 == INT32_MIN);

	assert(monopulse_compute_axis(2, 1, 4, &r) == 0);
	assert(r.valid == 0U);
	assert((r.flags & MONOPULSE_AXIS_DENOMINATOR_SMALL) != 0U);
}

static void test_invalid_arguments(void)
{
	struct monopulse_axis_result axis;
	struct monopulse_result result;
	struct monopulse_power_set powers = { 1, 1, 1, 1 };

	assert(monopulse_compute_axis(1, 1, 1, NULL) == -EINVAL);
	assert(monopulse_compute_axis(1, 1, 0, &axis) == -EINVAL);
	assert(monopulse_compute_result(NULL, 1, &result) == -EINVAL);
	assert(monopulse_compute_result(&powers, 1, NULL) == -EINVAL);
	assert(monopulse_compute_result(&powers, 0, &result) == -EINVAL);
}

static void test_axis_boundaries(void)
{
	struct monopulse_axis_result r;

	assert(monopulse_compute_axis(UINT64_MAX, UINT64_MAX, 1, &r) == 0);
	assert(r.denominator == UINT64_MAX);
	assert(r.numerator == 0);
	assert(r.error_q31 == 0);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);
	assert(r.valid == 1U);

	assert(monopulse_compute_axis(UINT64_MAX, 0, 1, &r) == 0);
	assert(r.numerator == INT64_MAX);
	assert(r.error_q31 == INT32_MAX);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);

	assert(monopulse_compute_axis(0, UINT64_MAX, 1, &r) == 0);
	assert(r.numerator == INT64_MIN);
	assert(r.error_q31 == INT32_MIN);
	assert((r.flags & MONOPULSE_AXIS_POWER_OVERFLOW) != 0U);
}

static void test_q31_rounding(void)
{
	struct monopulse_axis_result r;
	const uint64_t half_scale = UINT64_C(1) << 32;

	assert(monopulse_compute_axis(2, 1, 1, &r) == 0);
	assert(r.error_q31 == INT32_C(715827883));
	assert(monopulse_compute_axis(1, 2, 1, &r) == 0);
	assert(r.error_q31 == -INT32_C(715827883));

	/* 0.5 rounds down to the even integer zero. */
	assert(monopulse_compute_axis(half_scale + 1U, half_scale - 1U, 1,
				      &r) == 0);
	assert(r.error_q31 == 0);
	assert(monopulse_compute_axis(half_scale - 1U, half_scale + 1U, 1,
				      &r) == 0);
	assert(r.error_q31 == 0);

	/* 1.5 rounds up to the even integer two. */
	assert(monopulse_compute_axis(half_scale + 3U, half_scale - 3U, 1,
				      &r) == 0);
	assert(r.error_q31 == 2);
	assert(monopulse_compute_axis(half_scale - 3U, half_scale + 3U, 1,
				      &r) == 0);
	assert(r.error_q31 == -2);
}

static void test_independent_axes(void)
{
	struct monopulse_power_set powers = { 600, 200, 100, 300 };
	struct monopulse_result result;

	assert(monopulse_compute_result(&powers, 1, &result) == 0);
	assert(result.powers.az_plus == 600);
	assert(result.powers.el_minus == 300);
	assert(result.az.error_q31 == INT32_C(1073741824));
	assert(result.el.error_q31 == -INT32_C(1073741824));
	assert(result.az.valid == 1U);
	assert(result.el.valid == 1U);
}

static void test_state_sequence(void)
{
	static const struct monopulse_switch_outputs expected[MONOPULSE_STATE_COUNT] = {
		{0U, 0U}, {0U, 1U}, {1U, 0U}, {1U, 1U}
	};
	struct monopulse_switch_outputs actual;
	enum monopulse_state_id state = MONOPULSE_AZ_PLUS;

	for (uint32_t n = 0; n < MONOPULSE_STATE_COUNT; ++n) {
		assert(monopulse_state_outputs(state, &actual) == 0);
		assert(actual.delta_select == expected[n].delta_select);
		assert(actual.phase_180 == expected[n].phase_180);
		state = monopulse_next_state(state);
	}
	assert(state == MONOPULSE_AZ_PLUS);
}

static void test_invalid_sequence_arguments(void)
{
	struct monopulse_switch_outputs actual;
	const enum monopulse_state_id invalid_high = MONOPULSE_STATE_COUNT;
	const enum monopulse_state_id invalid_low =
		(enum monopulse_state_id)-1;

	assert(monopulse_state_outputs(invalid_high, &actual) == -EINVAL);
	assert(monopulse_state_outputs(invalid_low, &actual) == -EINVAL);
	assert(monopulse_state_outputs(MONOPULSE_AZ_PLUS, NULL) == -EINVAL);
	assert(monopulse_next_state(invalid_high) == MONOPULSE_AZ_PLUS);
	assert(monopulse_next_state(invalid_low) == MONOPULSE_AZ_PLUS);
}

int main(void)
{
	test_axis_vectors();
	test_invalid_arguments();
	test_axis_boundaries();
	test_q31_rounding();
	test_independent_axes();
	test_state_sequence();
	test_invalid_sequence_arguments();
	puts("PASS: monopulse foundation deterministic vectors passed.");
	return 0;
}
