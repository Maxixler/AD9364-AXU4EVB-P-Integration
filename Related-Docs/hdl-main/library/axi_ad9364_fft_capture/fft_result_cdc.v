`timescale 1ns/1ps

module fft_result_cdc #(
  parameter integer PAYLOAD_WIDTH = 160
) (
  input  wire                     adc_clk,
  input  wire                     adc_resetn,
  input  wire [15:0]              i_adc_epoch,
  input  wire                     i_adc_valid,
  input  wire [PAYLOAD_WIDTH-1:0] i_adc_payload,
  output wire                     o_adc_ready,
  output wire                     o_adc_busy,

  input  wire                     cpu_clk,
  input  wire                     cpu_resetn,
  input  wire [15:0]              i_cpu_epoch,
  output reg                      o_cpu_valid,
  output reg  [PAYLOAD_WIDTH-1:0] o_cpu_payload,
  output reg                      o_cpu_epoch_fault
);

  wire mailbox_resetn;
  wire domains_resetn;
  wire cpu_mailbox_resetn;
  wire adc_mailbox_resetn;
  wire cpu_domains_resetn;
  wire adc_domains_resetn;
  (* ASYNC_REG = "TRUE" *) reg [1:0] cpu_mailbox_reset_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] adc_mailbox_reset_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] cpu_domains_reset_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] adc_domains_reset_sync;
  reg request_toggle;
  reg [PAYLOAD_WIDTH+15:0] payload_hold;
  reg source_pending;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync1;
  (* ASYNC_REG = "TRUE" *) reg acknowledge_sync2;
  (* ASYNC_REG = "TRUE" *) reg cpu_ready_sync1;
  (* ASYNC_REG = "TRUE" *) reg cpu_ready_sync2;

  (* ASYNC_REG = "TRUE" *) reg request_sync1;
  (* ASYNC_REG = "TRUE" *) reg request_sync2;
  (* ASYNC_REG = "TRUE" *) reg pending_sync1;
  (* ASYNC_REG = "TRUE" *) reg pending_sync2;
  (* ASYNC_REG = "TRUE" *) reg adc_up_sync1;
  (* ASYNC_REG = "TRUE" *) reg adc_up_sync2;
  reg acknowledge_toggle;
  reg request_seen;
  reg cpu_ready;
  reg [1:0] arm_count;

  wire accept_request;
  wire recover_request;
  wire align_idle;

  assign mailbox_resetn = adc_resetn || cpu_resetn;
  assign domains_resetn = adc_resetn && cpu_resetn;
  assign cpu_mailbox_resetn = cpu_mailbox_reset_sync[1];
  assign adc_mailbox_resetn = adc_mailbox_reset_sync[1];
  assign cpu_domains_resetn = cpu_domains_reset_sync[1];
  assign adc_domains_resetn = adc_domains_reset_sync[1];
  assign o_adc_busy = source_pending;
  assign o_adc_ready = adc_resetn && cpu_ready_sync2 &&
                       !source_pending;
  assign accept_request = cpu_ready && pending_sync2 &&
                          (request_sync2 != request_seen);
  assign recover_request = !cpu_ready && adc_up_sync2 &&
                           (arm_count == 2'd3) && pending_sync2 &&
                           (acknowledge_toggle != request_sync2);
  assign align_idle = !cpu_ready && adc_up_sync2 &&
                      (arm_count == 2'd3) && !pending_sync2;

  // Both reset classes assert asynchronously but release through two stages
  // in each receiving clock domain. mailbox_resetn is asserted only when
  // both sides are reset so parity survives a one-sided reset; domains_resetn
  // is asserted by either side and safely re-arms the receiving state.
  always @(posedge cpu_clk or negedge mailbox_resetn) begin
    if (!mailbox_resetn)
      cpu_mailbox_reset_sync <= 2'b00;
    else
      cpu_mailbox_reset_sync <= {cpu_mailbox_reset_sync[0], 1'b1};
  end

  always @(posedge adc_clk or negedge mailbox_resetn) begin
    if (!mailbox_resetn)
      adc_mailbox_reset_sync <= 2'b00;
    else
      adc_mailbox_reset_sync <= {adc_mailbox_reset_sync[0], 1'b1};
  end

  always @(posedge cpu_clk or negedge domains_resetn) begin
    if (!domains_resetn)
      cpu_domains_reset_sync <= 2'b00;
    else
      cpu_domains_reset_sync <= {cpu_domains_reset_sync[0], 1'b1};
  end

  always @(posedge adc_clk or negedge domains_resetn) begin
    if (!domains_resetn)
      adc_domains_reset_sync <= 2'b00;
    else
      adc_domains_reset_sync <= {adc_domains_reset_sync[0], 1'b1};
  end

  always @(posedge adc_clk or negedge adc_mailbox_resetn) begin
    if (!adc_mailbox_resetn) begin
      request_toggle <= 1'b0;
      payload_hold <= {(PAYLOAD_WIDTH+16){1'b0}};
    end else if (adc_resetn && i_adc_valid && o_adc_ready) begin
      payload_hold <= {i_adc_epoch, i_adc_payload};
      request_toggle <= !request_toggle;
    end
  end

  always @(posedge adc_clk or negedge adc_resetn) begin
    if (!adc_resetn) begin
      source_pending <= 1'b0;
    end else if (i_adc_valid && o_adc_ready) begin
      source_pending <= 1'b1;
    end else if (source_pending && cpu_ready_sync2 &&
                 (acknowledge_sync2 == request_toggle)) begin
      source_pending <= 1'b0;
    end
  end

  always @(posedge adc_clk or negedge adc_domains_resetn) begin
    if (!adc_domains_resetn) begin
      acknowledge_sync1 <= 1'b0;
      acknowledge_sync2 <= 1'b0;
      cpu_ready_sync1 <= 1'b0;
      cpu_ready_sync2 <= 1'b0;
    end else begin
      acknowledge_sync1 <= acknowledge_toggle;
      acknowledge_sync2 <= acknowledge_sync1;
      cpu_ready_sync1 <= cpu_ready;
      cpu_ready_sync2 <= cpu_ready_sync1;
    end
  end

  always @(posedge cpu_clk or negedge cpu_domains_resetn) begin
    if (!cpu_domains_resetn) begin
      request_sync1 <= 1'b0;
      request_sync2 <= 1'b0;
      pending_sync1 <= 1'b0;
      pending_sync2 <= 1'b0;
      adc_up_sync1 <= 1'b0;
      adc_up_sync2 <= 1'b0;
      request_seen <= 1'b0;
      cpu_ready <= 1'b0;
      arm_count <= 2'd0;
      o_cpu_valid <= 1'b0;
      o_cpu_payload <= {PAYLOAD_WIDTH{1'b0}};
      o_cpu_epoch_fault <= 1'b0;
    end else begin
      request_sync1 <= request_toggle;
      request_sync2 <= request_sync1;
      pending_sync1 <= source_pending;
      pending_sync2 <= pending_sync1;
      adc_up_sync1 <= adc_resetn;
      adc_up_sync2 <= adc_up_sync1;
      o_cpu_valid <= 1'b0;
      o_cpu_epoch_fault <= 1'b0;

      if (!adc_up_sync2) begin
        request_seen <= request_sync2;
        cpu_ready <= 1'b0;
        arm_count <= 2'd0;
      end else if (!cpu_ready) begin
        if (arm_count != 2'd3) begin
          arm_count <= arm_count + 1'b1;
        end else begin
          request_seen <= request_sync2;
          cpu_ready <= 1'b1;
          if (pending_sync2 &&
              (acknowledge_toggle != request_sync2)) begin
            if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_cpu_epoch) begin
              o_cpu_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
              o_cpu_valid <= 1'b1;
            end else begin
              o_cpu_epoch_fault <= 1'b1;
            end
          end
        end
      end else if (accept_request) begin
        request_seen <= request_sync2;
        if (payload_hold[PAYLOAD_WIDTH+15:PAYLOAD_WIDTH] == i_cpu_epoch) begin
          o_cpu_payload <= payload_hold[PAYLOAD_WIDTH-1:0];
          o_cpu_valid <= 1'b1;
        end else begin
          o_cpu_epoch_fault <= 1'b1;
        end
      end
    end
  end

  always @(posedge cpu_clk or negedge cpu_mailbox_resetn) begin
    if (!cpu_mailbox_resetn) begin
      acknowledge_toggle <= 1'b0;
    end else if (cpu_resetn &&
                 (accept_request || recover_request || align_idle)) begin
      acknowledge_toggle <= request_sync2;
    end
  end

endmodule
