#ifdef PL_FFT_ETHERNET

#include <stddef.h>

#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/timeouts.h"
#include "netif/xadapter.h"
#include "xil_exception.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xstatus.h"
#include "xttcps.h"

#include "pl_fft_lwip_platform.h"
#include "pl_fft_udp_protocol.h"

#ifndef XPAR_XEMACPS_0_BASEADDR
#error "Candidate XSA is missing GEM3"
#endif
#if XPAR_XEMACPS_0_BASEADDR != 0xFF0E0000U
#error "Candidate XSA GEM3 base address changed"
#endif

#define PL_FFT_LWIP_TIMER_RATE_HZ 4u

static XTtcPs pl_fft_lwip_timer;
static volatile uint8_t pl_fft_lwip_timer_pending;

static void pl_fft_lwip_timer_handler(void *context)
{
	XTtcPs *timer = context;
	uint32_t status;

	status = XTtcPs_GetInterruptStatus(timer);
	XTtcPs_ClearInterruptStatus(timer, status);
	pl_fft_lwip_timer_pending = 1u;
}

static int32_t pl_fft_lwip_setup_interrupts(void)
{
	XTtcPs_Config *timer_config;
	uint16_t interval;
	uint8_t prescaler;
	int32_t status;

	timer_config = XTtcPs_LookupConfig(XPAR_XTTCPS_0_DEVICE_ID);
	if (timer_config == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	status = XTtcPs_CfgInitialize(&pl_fft_lwip_timer, timer_config,
				      timer_config->BaseAddress);
	if (status != XST_SUCCESS)
		return status;
	XTtcPs_SetOptions(&pl_fft_lwip_timer,
			  XTTCPS_OPTION_INTERVAL_MODE |
			  XTTCPS_OPTION_WAVE_DISABLE);
	XTtcPs_CalcIntervalFromFreq(&pl_fft_lwip_timer,
				    PL_FFT_LWIP_TIMER_RATE_HZ,
				    &interval, &prescaler);
	XTtcPs_SetInterval(&pl_fft_lwip_timer, interval);
	XTtcPs_SetPrescaler(&pl_fft_lwip_timer, prescaler);

	Xil_ExceptionInit();
	status = XScuGic_DeviceInitialize(XPAR_SCUGIC_SINGLE_DEVICE_ID);
	if (status != XST_SUCCESS)
		return status;
	Xil_ExceptionRegisterHandler(
		XIL_EXCEPTION_ID_IRQ_INT,
		(Xil_ExceptionHandler)XScuGic_DeviceInterruptHandler,
		(void *)XPAR_SCUGIC_SINGLE_DEVICE_ID);
	XScuGic_RegisterHandler(
		XPAR_SCUGIC_0_CPU_BASEADDR, XPAR_XTTCPS_0_INTR,
		(Xil_ExceptionHandler)pl_fft_lwip_timer_handler,
		(void *)&pl_fft_lwip_timer);
	XScuGic_EnableIntr(XPAR_SCUGIC_0_DIST_BASEADDR,
			   XPAR_XTTCPS_0_INTR);
	return PL_FFT_UDP_OK;
}

static void pl_fft_lwip_enable_interrupts(void)
{
	Xil_ExceptionEnableMask(XIL_EXCEPTION_IRQ);
	XScuGic_EnableIntr(XPAR_SCUGIC_0_DIST_BASEADDR,
			   XPAR_XTTCPS_0_INTR);
	XTtcPs_EnableInterrupts(&pl_fft_lwip_timer,
				XTTCPS_IXR_INTERVAL_MASK);
	XTtcPs_Start(&pl_fft_lwip_timer);
}

int32_t pl_fft_lwip_platform_init(
	struct pl_fft_lwip_platform *platform,
	const uint8_t board_ip[4],
	const uint8_t netmask[4],
	const uint8_t mac[6])
{
	ip_addr_t address;
	ip_addr_t mask;
	ip_addr_t gateway;
	int32_t status;

	if (platform == NULL || board_ip == NULL ||
	    netmask == NULL || mac == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	status = pl_fft_lwip_setup_interrupts();
	if (status != PL_FFT_UDP_OK)
		return status;

	IP4_ADDR(&address, board_ip[0], board_ip[1],
		 board_ip[2], board_ip[3]);
	IP4_ADDR(&mask, netmask[0], netmask[1],
		 netmask[2], netmask[3]);
	IP4_ADDR(&gateway, 0u, 0u, 0u, 0u);
	lwip_init();
	if (xemac_add(&platform->netif, &address, &mask, &gateway,
		      (unsigned char *)mac,
		      XPAR_XEMACPS_0_BASEADDR) == NULL)
		return PL_FFT_UDP_ERR_ARGUMENT;
	netif_set_default(&platform->netif);
	netif_set_up(&platform->netif);
	pl_fft_lwip_enable_interrupts();
	return PL_FFT_UDP_OK;
}

void pl_fft_lwip_platform_poll(struct pl_fft_lwip_platform *platform)
{
	if (platform == NULL)
		return;
	xemacif_input(&platform->netif);
	if (pl_fft_lwip_timer_pending != 0u) {
		pl_fft_lwip_timer_pending = 0u;
		sys_check_timeouts();
	}
}

#endif
