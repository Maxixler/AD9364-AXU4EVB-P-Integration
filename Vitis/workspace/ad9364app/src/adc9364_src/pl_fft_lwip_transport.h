#ifndef PL_FFT_LWIP_TRANSPORT_H
#define PL_FFT_LWIP_TRANSPORT_H

#ifdef PL_FFT_ETHERNET

#include <stdint.h>

#include "lwip/ip_addr.h"
#include "lwip/udp.h"

#include "pl_fft_lwip_platform.h"

struct pl_fft_lwip_transport {
	struct udp_pcb *pcb;
	ip_addr_t target;
	struct pl_fft_lwip_platform platform;
};

int32_t pl_fft_lwip_transport_init(
	struct pl_fft_lwip_transport *transport);
int32_t pl_fft_lwip_transport_send(
	void *context, const uint8_t *header, uint32_t header_bytes,
	const uint8_t *payload, uint32_t payload_bytes);

#endif

#endif
