`timescale 1ns/1ps

module fft_command_cdc #(
  parameter integer PAYLOAD_WIDTH = 64
) (
  input  wire                     cpu_clk,
  input  wire                     cpu_resetn,
  input  wire [15:0]              i_cpu_epoch,
  input  wire                     i_cpu_valid,
  input  wire [PAYLOAD_WIDTH-1:0] i_cpu_payload,
  output wire                     o_cpu_ready,
  output wire                     o_cpu_busy,

  input  wire                     adc_clk,
  input  wire                     adc_resetn,
  input  wire [15:0]              i_adc_epoch,
  output reg                      o_adc_valid,
  output reg  [PAYLOAD_WIDTH-1:0] o_adc_payload,
  output reg                      o_adc_epoch_fault
);

  wire mailbox_resetn;
  reg request_toggle;
  reg [PAYLOAD_WIDTH+15:0] payload_hold;
  reg source_pending;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;
  (* ASYNC_REG = "TRUE" *) reg adc_ready_sync1;
  (* ASYNC_REG = "TRUE" *) reg adc_ready_sync2;

  (* ASYNC_REG = "TRUE" *) reg request_sync1;
  (* ASYNC_REG = "TRUE" *) reg request_sync2;
  (* ASYNC_REG = "TRUE" *) reg pending_sync1;
  (* ASYNC_REG = "TRUE" *) reg pending_sync2;
  (* ASYNC_REG = "TRUE" *) reg cpu_up_sync1;
  (* ASYNC_REG = "TRUE" *) reg cpu_up_sync2;
  reg acknowledge_toggle;
  reg request_seen;
  reg adc_ready;
  reg [1:0] arm_count;

  wire accept_request;
  wire recover_request;
  wire align_idle;

  // Protocol parity is initialized only by a common reset. One-sided resets
  // retain it, so reset itself cannot manufacture a request/acknowledge edge.
  assign mailbox_resetn = cpu_resetn || adc_resetn;
  assign o_cpu_busy = source_pending;
  assign o_cpu_ready = cpu_resetn && adc_resetn && adc_ready_sync2 &&
                       !source_pending;
  assign accept_request = adc_ready && pending_sync2 &&
                          (request_sync2 != request_seen);
  assign recover_request = !adc_ready && cpu_up_sync2 &&
                           (arm_count == 2'd3) && pending_sync2;
  assign align_idle = !adc_ready && cpu_up_sync2 &&
                      (arm_count == 2'd3) && !pending_sync2;

  // The bundled payload and request parity survive a source-only reset. The
  // pending level is reset separately to cancel that source's old epoch.
  always @(posedge cpu_clk or negedge mailbox_resetn) begin
    if (!mailbox_resetn) begin
      request_toggle <= 1'b0;
      payload_hold <= {(PAYLOAD_WIDTH+16){1'b0}};
    end else if (cpu_resetn && i_cpu_valid && o_cpu_ready) begin
      payload_hold <= {i_cpu_epoch, i_cpu_payload};
      request_toggle <= !request_toggle;
    end
  end

  always @(posedge cpu_clk or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      source_pending <= 1'b0;
    end else if (i_cpu_valid && o_cpu_ready) begin
      source_pending <= 1'b1;
    end else if (source_pending && adc_ready_sync2 &&
                 (acknowledge_sync2 == request_toggle)) begin
      source_pending <= 1'b0;
    end
  end

  // Reset both synchronizer chains immediately on either-side reset. This
  // prevents a stale synchronized ready from accepting during reset-release
  // latency and requires a fresh destination-ready round trip.
  always @(posedge cpu_clk or negedge cpu_resetn or negedge adc_resetn) begin
    if (!cpu_resetn || !adc_resetn) begin
      acknowledge_sync1 <= 1'b0;
      acknowledge_sync2 <= 1'b0;
      adc_ready_sync1 <= 1'b0;
      adc_ready_sync2 <= 1'b0;
    end else begin
      acknowledge_sync1 <= acknowledge_toggle;
      acknowledge_sync2 <= acknowledge_sync1;
      adc_ready_sync1 <= adc_ready;
      adc_ready_sync2 <= adc_ready_sync1;
    end
  end

  always @(posedge adc_clk or negedge adc_resetn or negedge cpu_resetn) begin
    if (!adc_resetn || !cpu_resetn) begin
      request_sync1 <= 1'b0;
      request_sync2 <= 1'b0;
      pending_sync1 <= 1'b0;
      pending_sync2 <= 1'b0;
      cpu_up_sync1 <= 1'b0;
      cpu_up_sync2 <= 1'b0;
      request_seen <= 1'b0;
      adc_ready <= 1'b0;
      arm_count <= 2'd0;
      o_adc_valid <= 1'b0;
      o_adc_payload <= {PAYLOAD_WIDTH{1'b0}};
      o_adc_epoch_fault <= 1'b0;
    end else begin
      request_sync1 <= request_toggle;
      request_sync2 <= request_sync1;
      pending_sync1 <= source_pending;
      pending_sync2 <= pending_sync1;
      cpu_up_sync1 <= cpu_resetn;
      cpu_up_sync2 <= cpu_up_sync1;
      o_adc_valid <= 1'b0;
      o_adc_epoch_fault <= 1'b0;

      if (!cpu_up_sync2) begin
        request_seen <= request_sync2;
        adc_ready <= 1'b0;
        arm_count <= 2'd0;
      end else if (!adc_ready) begin
        if (arm_count != 2'd3) begin
          arm_count <= arm_count + 1'b1;
        end else begin
          request_seen <= request_sync2;
          adc_ready <= 1'b1;
          if (pending_sync2) begin
            if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_adc_epoch) begin
              o_adc_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
              o_adc_valid <= 1'b1;
            end else begin
              o_adc_epoch_fault <= 1'b1;
            end
          end
        end
      end else if (accept_request) begin
        request_seen <= request_sync2;
        if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_adc_epoch) begin
          o_adc_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
          o_adc_valid <= 1'b1;
        end else begin
          o_adc_epoch_fault <= 1'b1;
        end
      end
    end
  end

  // Acknowledge parity also survives a one-sided reset. Pending work is
  // acknowledged only on the same edge that it is delivered/rejected.
  always @(posedge adc_clk or negedge mailbox_resetn) begin
    if (!mailbox_resetn) begin
      acknowledge_toggle <= 1'b0;
    end else if (adc_resetn && cpu_resetn &&
                 (accept_request || recover_request || align_idle)) begin
      acknowledge_toggle <= request_sync2;
    end
  end

endmodule
