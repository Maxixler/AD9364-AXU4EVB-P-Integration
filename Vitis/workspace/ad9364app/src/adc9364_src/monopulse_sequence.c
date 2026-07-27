#include "monopulse_sequence.h"

#include <errno.h>
#include <stddef.h>

static const struct monopulse_switch_outputs monopulse_state_map[
	MONOPULSE_STATE_COUNT] = {
	[MONOPULSE_AZ_PLUS] = {0U, 0U},
	[MONOPULSE_AZ_MINUS] = {0U, 1U},
	[MONOPULSE_EL_PLUS] = {1U, 0U},
	[MONOPULSE_EL_MINUS] = {1U, 1U}
};

int32_t monopulse_state_outputs(enum monopulse_state_id state,
				struct monopulse_switch_outputs *out)
{
	if ((out == NULL) || (state < MONOPULSE_AZ_PLUS) ||
	    (state >= MONOPULSE_STATE_COUNT)) {
		return -EINVAL;
	}

	*out = monopulse_state_map[state];
	return 0;
}

enum monopulse_state_id monopulse_next_state(enum monopulse_state_id state)
{
	switch (state) {
	case MONOPULSE_AZ_PLUS:
		return MONOPULSE_AZ_MINUS;
	case MONOPULSE_AZ_MINUS:
		return MONOPULSE_EL_PLUS;
	case MONOPULSE_EL_PLUS:
		return MONOPULSE_EL_MINUS;
	case MONOPULSE_EL_MINUS:
		return MONOPULSE_AZ_PLUS;
	default:
		return MONOPULSE_AZ_PLUS;
	}
}
