#ifndef PL_FFT_LWIP_PLATFORM_H
#define PL_FFT_LWIP_PLATFORM_H

#ifdef PL_FFT_ETHERNET

#include <stdint.h>

#include "lwip/netif.h"

struct pl_fft_lwip_platform {
	struct netif netif;
};

int32_t pl_fft_lwip_platform_init(
	struct pl_fft_lwip_platform *platform,
	const uint8_t board_ip[4],
	const uint8_t netmask[4],
	const uint8_t mac[6]);
void pl_fft_lwip_platform_poll(struct pl_fft_lwip_platform *platform);

#endif

#endif
