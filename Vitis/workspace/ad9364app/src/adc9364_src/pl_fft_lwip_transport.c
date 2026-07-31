#ifdef PL_FFT_ETHERNET

#include <stddef.h>
#include <string.h>

#include "lwip/err.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"

#include "pl_fft_lwip_transport.h"
#include "pl_fft_udp_protocol.h"

static const uint8_t board_ip[4] = {192u, 168u, 1u, 10u};
static const uint8_t target_ip[4] = {192u, 168u, 1u, 100u};
static const uint8_t netmask[4] = {255u, 255u, 255u, 0u};
static const uint8_t mac[6] = {
	0x02u, 0x00u, 0x00u, 0x93u, 0x64u, 0x01u
};

int32_t pl_fft_lwip_transport_init(
	struct pl_fft_lwip_transport *transport)
{
	int32_t status;

	if (transport == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	memset(transport, 0, sizeof(*transport));
	status = pl_fft_lwip_platform_init(
		&transport->platform, board_ip, netmask, mac);
	if (status != PL_FFT_UDP_OK)
		return status;
	IP4_ADDR(&transport->target, target_ip[0], target_ip[1],
		 target_ip[2], target_ip[3]);
	transport->pcb = udp_new();
	if (transport->pcb == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	return PL_FFT_UDP_OK;
}

int32_t pl_fft_lwip_transport_send(
	void *context, const uint8_t *header, uint32_t header_bytes,
	const uint8_t *payload, uint32_t payload_bytes)
{
	struct pl_fft_lwip_transport *transport = context;
	struct pbuf *packet;
	uint16_t bin_count;
	err_t err;

	if (transport == NULL || transport->pcb == NULL ||
	    header == NULL || payload == NULL ||
	    header_bytes != PL_FFT_UDP_HEADER_BYTES ||
	    payload_bytes == 0u ||
	    payload_bytes > PL_FFT_UDP_BINS_PER_CHUNK * sizeof(uint64_t) ||
	    payload_bytes % sizeof(uint64_t) != 0u)
		return PL_FFT_UDP_ERR_ARGUMENT;
	bin_count = (uint16_t)(payload_bytes / sizeof(uint64_t));
	packet = pbuf_alloc(PBUF_TRANSPORT,
			    (uint16_t)(64u + bin_count * 8u),
			    PBUF_RAM);
	if (packet == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	memcpy(packet->payload, header, PL_FFT_UDP_HEADER_BYTES);
	memcpy((uint8_t *)packet->payload + PL_FFT_UDP_HEADER_BYTES,
	       payload, payload_bytes);
	err = udp_sendto(transport->pcb, packet, &transport->target, 5005u);
	pbuf_free(packet);
	if (err != ERR_OK)
		return (int32_t)err;
	return PL_FFT_UDP_OK;
}

#endif
