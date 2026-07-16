#ifndef WIFI_RF_TEST_H
#define WIFI_RF_TEST_H

#include <stddef.h>
#include <stdint.h>

struct ad9361_rf_phy;
struct axi_dmac;

#define WIFI_RF_TEST_PASS 0
#define WIFI_RF_TEST_INCONCLUSIVE 1

int32_t wifi_rf_test_run(struct ad9361_rf_phy *phy,
			 struct axi_dmac *rx_dmac,
			 int16_t *iq_buffer,
			 size_t complex_samples);

#endif
