#ifndef MONOPULSE_SEQUENCE_H
#define MONOPULSE_SEQUENCE_H

#include <stdint.h>

enum monopulse_state_id {
	MONOPULSE_AZ_PLUS = 0,
	MONOPULSE_AZ_MINUS = 1,
	MONOPULSE_EL_PLUS = 2,
	MONOPULSE_EL_MINUS = 3,
	MONOPULSE_STATE_COUNT = 4
};

struct monopulse_switch_outputs {
	uint8_t delta_select;
	uint8_t phase_180;
};

int32_t monopulse_state_outputs(enum monopulse_state_id state,
				struct monopulse_switch_outputs *out);
enum monopulse_state_id monopulse_next_state(enum monopulse_state_id state);

#endif
