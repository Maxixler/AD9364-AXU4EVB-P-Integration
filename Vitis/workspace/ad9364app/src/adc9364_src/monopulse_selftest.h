#ifndef MONOPULSE_SELFTEST_H
#define MONOPULSE_SELFTEST_H

#include <stdint.h>

struct ad9361_rf_phy;

int32_t monopulse_selftest_run(struct ad9361_rf_phy *phy);

#endif
